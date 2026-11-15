"""BioCLIP 2 serving classifier: open_clip ViT-L/14 image encoder + a trained T1 linear head (or T0 text head).

`wildlife.train --tier t1` and `scripts/local_bioclip2_t1.py` write `bioclip2_linear_head.npz`; before this
module, nothing in the serving path loaded it, so `/v2/predict` ran an untrained numpy stub.

Enable with `WILDLIFE_BIOCLIP2_HEAD=/path/to/bioclip2_linear_head.npz` (requires torch + open_clip_torch).
"""

from __future__ import annotations

from pathlib import Path
from typing import List, Optional

import numpy as np

BIOCLIP2_HUB_ID = "hf-hub:imageomics/bioclip-2"


class BioCLIP2ServingClassifier:
    """Classifier exposing `forward_logits_rgb(rgb_uint8_hwc) -> [1, 20]` for `WildlifePipeline`."""

    backend = "bioclip2_open_clip"

    def __init__(self, head_path: Path, class_ids: List[str], use_text_head: bool = False) -> None:
        import open_clip  # type: ignore
        import torch  # type: ignore

        self._torch = torch
        self.device = (
            "cuda" if torch.cuda.is_available() else ("mps" if torch.backends.mps.is_available() else "cpu")
        )
        model, _, preprocess = open_clip.create_model_and_transforms(BIOCLIP2_HUB_ID)
        self.model = model.to(self.device).eval()
        self.preprocess = preprocess

        head = np.load(Path(head_path), allow_pickle=False)
        head_ids = [str(c) for c in head["class_ids"]] if "class_ids" in head else list(class_ids)
        if head_ids != list(class_ids):
            raise ValueError(f"BioCLIP 2 head class order {head_ids} != taxonomy order {list(class_ids)}")
        self.class_ids = list(class_ids)
        self.num_classes = len(class_ids)
        if use_text_head:
            # T0 zero-shot: cosine similarity * CLIP logit scale
            self.W = head["text_matrix"].astype(np.float32) * 100.0
            self.b = np.zeros(self.num_classes, dtype=np.float32)
            self.tier = "t0"
        else:
            self.W = head["weights"].astype(np.float32)
            self.b = head["bias"].astype(np.float32)
            self.tier = "t1"

    def embed_rgb(self, rgb: np.ndarray) -> np.ndarray:
        from PIL import Image

        torch = self._torch
        x = self.preprocess(Image.fromarray(np.ascontiguousarray(rgb[:, :, :3]).astype(np.uint8))).unsqueeze(0)
        with torch.no_grad():
            f = self.model.encode_image(x.to(self.device))
            f = torch.nn.functional.normalize(f, dim=-1)
        return f.float().cpu().numpy()

    def forward_logits_rgb(self, rgb: np.ndarray) -> np.ndarray:
        emb = self.embed_rgb(rgb)
        return emb @ self.W.T + self.b

    def forward_logits(self, chw: np.ndarray) -> np.ndarray:  # pragma: no cover - pipeline uses the RGB path
        raise NotImplementedError("BioCLIP2ServingClassifier needs raw RGB crops; call forward_logits_rgb")


def load_from_env(class_ids: List[str]) -> Optional[BioCLIP2ServingClassifier]:
    import os

    head = os.environ.get("WILDLIFE_BIOCLIP2_HEAD")
    if not head:
        return None
    return BioCLIP2ServingClassifier(
        Path(head), class_ids, use_text_head=os.environ.get("WILDLIFE_BIOCLIP2_TIER", "t1") == "t0"
    )
