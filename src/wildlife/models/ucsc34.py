"""Inference wrapper for the fine-tuned 34-class UCSC BioCLIP 2 adapter.

The Colab run (`notebooks/12_UCSC_34_CLASSES_BUGS_SLUGS_TREES_GPU.ipynb`) saves
`model_adapter.pt` with format `ucsc-bioclip-v4-adapter`. It holds only what
training changed (the last visual blocks, `ln_post`, `proj`) plus the linear
head, the class list, and the calibration temperature. The frozen BioCLIP 2
base weights are fetched from Hugging Face at the pinned `base_revision`.

This is a closed-set whole-photo classifier. It always answers with one of the
34 classes, so callers should treat low probabilities as "not sure".
"""

from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import threading
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RUN_DIR = ROOT / "runs" / "ucsc34_bioclip_v4"
ADAPTER_FORMAT = "ucsc-bioclip-v4-adapter"
MODEL_VERSION = "ucsc34-bioclip2-v4"
LOW_CONFIDENCE_THRESHOLD = 0.50


class AdapterError(RuntimeError):
    """Raised when the adapter artifact is missing, corrupt, or the wrong format."""


def default_run_dir() -> Path:
    return Path(os.environ.get("WILDLIFE_UCSC34_RUN_DIR", str(DEFAULT_RUN_DIR)))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


class Ucsc34Classifier:
    """BioCLIP 2 ViT-L/14 visual tower + fine-tuned delta + 34-way linear head."""

    def __init__(
        self,
        run_dir: Optional[Path] = None,
        device: Optional[str] = None,
        verify_checksum: bool = True,
    ) -> None:
        import torch
        import open_clip
        import safetensors.torch
        from huggingface_hub import snapshot_download

        self.run_dir = Path(run_dir) if run_dir is not None else default_run_dir()
        adapter_path = self.run_dir / "model_adapter.pt"
        if not adapter_path.exists():
            raise AdapterError(f"Adapter weights not found at {adapter_path}.")

        self.sha256 = _sha256(adapter_path)
        checksum_path = self.run_dir / "model_checksum.json"
        if verify_checksum and checksum_path.exists():
            expected = json.loads(checksum_path.read_text())["sha256"]
            if expected != self.sha256:
                raise AdapterError(
                    f"model_adapter.pt SHA-256 {self.sha256} does not match model_checksum.json {expected}."
                )

        artifact = torch.load(adapter_path, map_location="cpu", weights_only=True)
        if artifact.get("format") != ADAPTER_FORMAT:
            raise AdapterError(f"Unexpected adapter format: {artifact.get('format')!r}.")

        self.classes: List[Dict[str, Any]] = sorted(artifact["classes"], key=lambda c: int(c["index"]))
        self.temperature = float(artifact["temperature"])
        self.base_repo = str(artifact["base_repo"])
        self.base_revision = str(artifact["base_revision"])
        preprocess_cfg = dict(artifact.get("preprocess_cfg") or {})

        model_dir = Path(
            snapshot_download(
                self.base_repo,
                revision=self.base_revision,
                allow_patterns=["open_clip_config.json", "open_clip_model.safetensors"],
            )
        )
        architecture = self.run_dir / "ucsc_bioclip.json"
        if not architecture.exists():
            base_cfg = json.loads((model_dir / "open_clip_config.json").read_text())
            architecture.write_text(json.dumps(base_cfg["model_cfg"], indent=2))
        open_clip.add_model_config(architecture)

        # Same construction as training so the eval transform is identical.
        model, _, eval_transform = open_clip.create_model_and_transforms(
            "ucsc_bioclip",
            pretrained=None,
            image_mean=preprocess_cfg.get("mean"),
            image_std=preprocess_cfg.get("std"),
            image_interpolation=preprocess_cfg.get("interpolation", "bicubic"),
            image_resize_mode=preprocess_cfg.get("resize_mode", "shortest"),
        )
        visual = model.visual
        del model
        base_state = safetensors.torch.load_file(str(model_dir / "open_clip_model.safetensors"))
        visual.load_state_dict(
            {k[len("visual."):]: v for k, v in base_state.items() if k.startswith("visual.")}
        )
        del base_state

        named = dict(visual.named_parameters())
        delta = artifact["visual_delta"]
        unknown = sorted(set(delta) - set(named))
        if unknown:
            raise AdapterError(f"Adapter has parameters the base model lacks: {unknown[:5]}")
        with torch.no_grad():
            for name, tensor in delta.items():
                named[name].copy_(tensor.to(named[name].dtype))

        head_state = artifact["head"]
        out_features, in_features = head_state["weight"].shape
        if out_features != len(self.classes):
            raise AdapterError(
                f"Head has {out_features} outputs but the adapter lists {len(self.classes)} classes."
            )
        head = torch.nn.Linear(in_features, out_features)
        head.load_state_dict(head_state)

        if device is None:
            device = os.environ.get("WILDLIFE_DEVICE") or (
                "cuda" if torch.cuda.is_available()
                else "mps" if torch.backends.mps.is_available()
                else "cpu"
            )
        self.device = device
        self._torch = torch
        self._visual = visual.to(device).eval()
        self._head = head.to(device).eval()
        self._transform = eval_transform
        self._lock = threading.Lock()
        self.model_version = MODEL_VERSION

    @property
    def num_classes(self) -> int:
        return len(self.classes)

    def predict_image(self, image: Any, top_k: int = 3) -> Dict[str, Any]:
        """Classify one PIL image. Returns calibrated top-k probabilities."""
        from PIL import ImageOps

        torch = self._torch
        rgb = ImageOps.exif_transpose(image).convert("RGB")
        batch = self._transform(rgb).unsqueeze(0).to(self.device)
        with self._lock, torch.no_grad():
            features = torch.nn.functional.normalize(self._visual(batch), dim=-1)
            logits = self._head(features).float().cpu()[0]
        probabilities = (logits / self.temperature).softmax(0)
        k = max(1, min(int(top_k), self.num_classes))
        values, indices = probabilities.topk(k)
        predictions = []
        for probability, index in zip(values.tolist(), indices.tolist()):
            record = self.classes[index]
            predictions.append(
                {
                    "class_id": record["class_id"],
                    "common_name": record["common_name"],
                    "scientific_name": record["scientific_name"],
                    "group": record["group"],
                    "probability": round(float(probability), 6),
                }
            )
        return {
            "model_version": self.model_version,
            "top": predictions[0],
            "predictions": predictions,
            "low_confidence": predictions[0]["probability"] < LOW_CONFIDENCE_THRESHOLD,
        }

    def predict_bytes(self, raw_bytes: bytes, top_k: int = 3) -> Dict[str, Any]:
        from PIL import Image

        with Image.open(io.BytesIO(raw_bytes)) as image:
            return self.predict_image(image, top_k=top_k)


def load_classes(run_dir: Optional[Path] = None) -> List[Dict[str, Any]]:
    """Read the 34-class list without loading any weights."""
    path = (Path(run_dir) if run_dir is not None else default_run_dir()) / "classes.json"
    return sorted(json.loads(path.read_text()), key=lambda c: int(c["index"]))
