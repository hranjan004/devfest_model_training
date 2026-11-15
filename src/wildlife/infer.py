"""End-to-end wildlife inference delegating to `WildlifePipeline` (§9.1.1-2)."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any, Optional

import numpy as np

from wildlife.detect import CROP_VERSION_DEFAULT, DETECTOR_VERSION_DEFAULT
from wildlife.detect.megadetector import MegaDetectorV6Detector
from wildlife.models.argon import ArgonMultimodalAssistant
from wildlife.models.backbones import load_v2_checkpoint
from wildlife.models.classifier import WildlifeClassifier
from wildlife.models.unknown import UnknownSpeciesGate
from wildlife.pipeline import WildlifePipeline, parse_manual_box as parse_crop_box
from wildlife.schemas import PredictionResponse, load_species_taxonomy


class WildlifePredictor:
    """Stateful inference engine delegating to `WildlifePipeline` (§9.1.2)."""

    def __init__(
        self,
        checkpoint_path: Optional[Path] = None,
        enable_live_argon: bool = False,
        detector: Optional[Any] = None,
        expected_detector_version: str = DETECTOR_VERSION_DEFAULT,
        expected_crop_version: str = CROP_VERSION_DEFAULT,
        enforce_version_parity: bool = True,
    ) -> None:
        self.model_version = "species-v1.0"
        self.calibration_version = "temp-v1"
        self.rating_version = "quality-v1"
        self.argon_model_version = "gemini-4-argon"
        self.detector_version = expected_detector_version
        self.crop_version = expected_crop_version
        self.temperature = 1.0
        self.image_size = 224

        test_mode = os.environ.get("WILDLIFE_TEST_MODE", "1") == "1"

        from wildlife.models.bioclip2_serving import load_from_env

        bioclip = load_from_env([r.class_id for r in load_species_taxonomy()])
        if bioclip is not None:
            self.model = bioclip
            self.model_version = f"species-v2.0-{bioclip.tier}-bioclip2"
            if os.environ.get("WILDLIFE_TEMPERATURE"):
                self.temperature = float(os.environ["WILDLIFE_TEMPERATURE"])
        elif checkpoint_path and Path(checkpoint_path).exists():
            self.model, payload = load_v2_checkpoint(
                Path(checkpoint_path),
                expected_detector_version=expected_detector_version,
                expected_crop_version=expected_crop_version,
                enforce_version_parity=enforce_version_parity,
            )
            self.temperature = float(payload.get("temperature", 1.0))
            cfg = payload.get("config", {})
            self.image_size = int(
                payload.get("input_size") or cfg.get("image_size", 224)
            )
        else:
            self.model = WildlifeClassifier(
                num_classes=20,
                seed=42,
                pretrained=False,
                use_torch_if_available=(not test_mode),
            )

        self.detector = detector or MegaDetectorV6Detector(
            variant="MDV6-apa-rtdetr-e",
            tau_det=0.25,
            test_mode=True,
        )
        if not test_mode and hasattr(self.detector, "_try_load_pytorch_wildlife"):
            # Load MegaDetector weights on the main thread at startup; lazy loading inside a
            # FastAPI worker thread hangs the first request on macOS/MPS.
            self.detector._try_load_pytorch_wildlife()
        self.gate = UnknownSpeciesGate.from_config()
        self.argon = ArgonMultimodalAssistant(enable_live_api=enable_live_argon)
        self.species_records = load_species_taxonomy()

        self.pipeline = WildlifePipeline(
            detector=self.detector,
            classifier=self.model,
            gate=self.gate,
            argon=self.argon,
            temperature=self.temperature,
            classifier_input_size=self.image_size,
            model_version=self.model_version,
            calibration_version=self.calibration_version,
            rating_version=self.rating_version,
            crop_version=self.crop_version,
        )

    def predict_bytes(
        self,
        raw_bytes: bytes,
        crop_box: Optional[Any] = None,
        multiple_animals_reported: bool = False,
        scene_hint: Optional[str] = None,
        logits_override: Optional[np.ndarray] = None,
        explain: bool = False,
    ) -> PredictionResponse:
        return self.pipeline.run(
            raw_bytes=raw_bytes,
            manual_box=crop_box,
            multiple_animals_reported=multiple_animals_reported,
            scene_hint=scene_hint,
            logits_override=logits_override,
            explain=explain,
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=Path("runs/efficientnet_b0_v1/best.ckpt"),
    )
    parser.add_argument("--crop", type=str, default=None, help="x1,y1,x2,y2")
    parser.add_argument("--v2", action="store_true", help="Output /v2/predict multi-detection schema")
    args = parser.parse_args()

    predictor = WildlifePredictor(checkpoint_path=args.checkpoint)
    res = predictor.predict_bytes(args.image.read_bytes(), crop_box=args.crop)
    out = res.to_v2_dict() if args.v2 else res.to_dict()
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
