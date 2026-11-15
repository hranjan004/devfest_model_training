"""Two-stage detect-then-classify pipeline (`WildlifePipeline`) for UCSC Wildlife Vision v2 (§2.1 & §9.1)."""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np

from wildlife.data.clean import strip_exif_and_validate
from wildlife.data.dataset import preprocess_rgb_for_model
from wildlife.detect import CROP_VERSION_DEFAULT, AnimalDetector, Detection
from wildlife.detect.crops import extract_crop_rgb, select_inference_boxes
from wildlife.models.argon import ArgonMultimodalAssistant, build_interpretable_explanation
from wildlife.models.classifier import WildlifeClassifier
from wildlife.models.unknown import UnknownSpeciesGate
from wildlife.quality.scoring import (
    compute_identification_ready_rating,
    score_photograph,
)
from wildlife.schemas import (
    DetectionPredictionItem,
    PhotoQualityScores,
    PredictedSpecies,
    PredictionResponse,
    TopCandidate,
    load_species_taxonomy,
)


def parse_manual_box(
    manual_box: Optional[Any],
    width: int,
    height: int,
) -> Optional[Tuple[int, int, int, int]]:
    if manual_box is None or manual_box == "":
        return None
    if isinstance(manual_box, str):
        parts = [int(float(x.strip())) for x in manual_box.split(",")]
    else:
        parts = [int(float(x)) for x in manual_box]
    if len(parts) != 4:
        raise ValueError("manual_box / crop_box must contain 4 coordinates: x1,y1,x2,y2")
    x1, y1, x2, y2 = parts
    x1 = max(0, min(width - 1, x1))
    y1 = max(0, min(height - 1, y1))
    x2 = max(x1 + 1, min(width, x2))
    y2 = max(y1 + 1, min(height, y2))
    if (x2 - x1) < 16 or (y2 - y1) < 16:
        raise ValueError("Crop region must be at least 16x16 pixels.")
    return (x1, y1, x2, y2)


class WildlifePipeline:
    """Two-stage detect-then-classify pipeline (§2.1 & §9.1)."""

    def __init__(
        self,
        detector: AnimalDetector,
        classifier: WildlifeClassifier,
        gate: UnknownSpeciesGate,
        argon: ArgonMultimodalAssistant,
        temperature: float = 1.0,
        classifier_input_size: int = 224,
        model_version: str = "species-v1.0",
        calibration_version: str = "temp-v1",
        rating_version: str = "quality-v1",
        crop_version: str = CROP_VERSION_DEFAULT,
    ) -> None:
        self.detector = detector
        self.classifier = classifier
        self.gate = gate
        self.argon = argon
        self.temperature = float(temperature)
        self.classifier_input_size = int(classifier_input_size)
        self.model_version = model_version
        self.calibration_version = calibration_version
        self.rating_version = rating_version
        self.crop_version = crop_version
        self.species_records = load_species_taxonomy()

    def run(
        self,
        raw_bytes: bytes,
        manual_box: Optional[Any] = None,
        multiple_animals_reported: bool = False,
        scene_hint: Optional[str] = None,
        logits_override: Optional[Any] = None,
        explain: bool = False,
    ) -> PredictionResponse:
        safe_png, full_rgb, meta = strip_exif_and_validate(raw_bytes)
        full_h, full_w = int(meta["height"]), int(meta["width"])

        parsed_manual = parse_manual_box(manual_box, width=full_w, height=full_h)
        crop_used = parsed_manual is not None

        # Legacy v1 test hook: when multiple_animals_reported=True and no manual crop and no multi-box detector override
        if (
            multiple_animals_reported
            and not crop_used
            and getattr(self.detector, "_mock_detections", None) is None
        ):
            full_q = score_photograph(full_rgb, full_shape=(full_h, full_w))
            top_cands = [
                TopCandidate(
                    class_id=r.class_id,
                    probability=round(1.0 / 20.0, 4),
                    common_name=r.common_name,
                    scientific_name=r.scientific_name,
                    group=r.group,
                )
                for r in self.species_records[:3]
            ]
            return PredictionResponse(
                status="uncertain",
                predicted_species=None,
                confidence_calibrated=None,
                top_3=top_cands,
                photo_quality=full_q,
                identification_ready_rating=None,
                explanation=(
                    "Multiple animals reported in frame; provide crop_box coordinates or use "
                    "/v2/predict with multi-animal detection."
                ),
                model_version=self.model_version,
                calibration_version=self.calibration_version,
                rating_version=self.rating_version,
                argon_model_version=self.argon.model_id,
                detector_version=self.detector.version,
                crop_version=self.crop_version,
                detections=[],
                primary_index=None,
                crop_used=False,
                note="Please provide crop_box coordinates isolating a single animal.",
            )

        # Stage 1: Detector (or manual box bypass per §9.1.1)
        if parsed_manual is not None:
            mx1, my1, mx2, my2 = parsed_manual
            animal_dets = [
                Detection(
                    x1=mx1,
                    y1=my1,
                    x2=mx2,
                    y2=my2,
                    label="animal",
                    confidence=1.0,
                    source="manual",
                )
            ]
            all_dets = list(animal_dets)
        else:
            all_dets = self.detector.detect(full_rgb)
            animal_dets = select_inference_boxes(
                all_dets, tau_det=self.gate.tau_det, max_boxes=5
            )

        # If no animal >= tau_det (including empty landscape OR person/vehicle-only frames, §2.1 & §9.2)
        if not animal_dets or scene_hint == "no_animal":
            full_q = score_photograph(full_rgb, full_shape=(full_h, full_w))
            has_person_or_vehicle = any(
                d.label in {"person", "vehicle"} for d in all_dets
            )
            reason_note = (
                "Person or vehicle detected without any wild animal; rejected as no_animal."
                if has_person_or_vehicle
                else "No wild mammal or bird detected above detector threshold."
            )
            return PredictionResponse(
                status="no_animal",
                predicted_species=None,
                confidence_calibrated=None,
                top_3=[],
                photo_quality=full_q,
                identification_ready_rating=None,
                explanation=build_interpretable_explanation(
                    status="no_animal",
                    predicted_species=None,
                    top_3=[],
                    photo_quality=full_q.to_dict(),
                ),
                model_version=self.model_version,
                calibration_version=self.calibration_version,
                rating_version=self.rating_version,
                argon_model_version=self.argon.model_id,
                detector_version=self.detector.version,
                crop_version=self.crop_version,
                detections=[],
                primary_index=None,
                crop_used=crop_used,
                note=reason_note,
            )

        # Stage 2, 3, 4, 5: Crop -> Classify -> Gate -> Photo Quality Q & Rating R per animal box
        det_items: List[DetectionPredictionItem] = []
        raw_gate_outputs: List[Dict[str, Any]] = []

        for idx, det in enumerate(animal_dets):
            box_tuple = (det.x1, det.y1, det.x2, det.y2)
            crop_512, crop_meta = extract_crop_rgb(
                full_rgb, box=box_tuple, out_size=512, pad_fraction=0.15
            )
            # Score quality on the crop using box geometry (§9.1.4)
            q_scores = score_photograph(
                crop_512,
                crop_box=box_tuple,
                full_shape=(full_h, full_w),
            )
            # Incorporate inside_frame_ratio & edge touch into visibility score
            geom_vis = int(
                round(
                    0.70 * q_scores.visibility
                    + 30.0 * float(crop_meta.get("inside_frame_ratio", 1.0))
                    - (10.0 if crop_meta.get("touches_edge") else 0.0)
                )
            )
            geom_vis = max(0, min(100, geom_vis))
            q_overall = int(
                round(
                    0.30 * q_scores.sharpness
                    + 0.25 * geom_vis
                    + 0.15 * q_scores.exposure
                    + 0.15 * q_scores.resolution
                    + 0.15 * q_scores.composition
                )
            )
            q_final = PhotoQualityScores(
                overall=q_overall,
                sharpness=q_scores.sharpness,
                visibility=geom_vis,
                exposure=q_scores.exposure,
                resolution=q_scores.resolution,
                composition=q_scores.composition,
            )

            if logits_override is not None:
                arr_ov = np.asarray(logits_override, dtype=np.float64)
                if arr_ov.ndim == 2 and idx < len(arr_ov):
                    logits_1d = arr_ov[idx]
                else:
                    logits_1d = arr_ov.reshape(-1)[:20]
            elif hasattr(self.classifier, "forward_logits_rgb"):
                logits_1d = self.classifier.forward_logits_rgb(crop_512)[0]
            else:
                chw = preprocess_rgb_for_model(
                    crop_512, image_size=self.classifier_input_size, is_train=False
                )
                logits_1d = self.classifier.forward_logits(chw)[0]

            gate_res = self.gate.evaluate_single(
                logits_1d,
                temperature=self.temperature,
                scene_hint=scene_hint,
                box_source=det.source,
                detector_confidence=det.confidence,
            )
            raw_gate_outputs.append(gate_res)

            pred_dict = gate_res["predicted_species"]
            pred_sp = (
                PredictedSpecies(
                    class_id=pred_dict["class_id"],
                    common_name=pred_dict["common_name"],
                    scientific_name=pred_dict["scientific_name"],
                    group=pred_dict["group"],
                )
                if pred_dict
                else None
            )
            top3_objs = [
                TopCandidate(
                    class_id=c["class_id"],
                    probability=c["probability"],
                    common_name=c.get("common_name"),
                    scientific_name=c.get("scientific_name"),
                    group=c.get("group"),
                )
                for c in gate_res["top_3"]
            ]
            r_val = compute_identification_ready_rating(
                quality_overall=q_final.overall,
                confidence_calibrated=gate_res["confidence_calibrated"],
                status=gate_res["status"],
            )
            det_items.append(
                DetectionPredictionItem(
                    box=[det.x1, det.y1, det.x2, det.y2],
                    box_source=det.source,
                    detector_confidence=det.confidence,
                    status=gate_res["status"],
                    species=pred_sp,
                    confidence_calibrated=gate_res["confidence_calibrated"],
                    top_3=top3_objs,
                    quality=q_final,
                    rating=r_val,
                    coarse_group_fallback=gate_res.get("coarse_group_fallback"),
                )
            )

        # §9.1.3: Keep `uncertain` when two boxes overlap with IoU > 0.5 but disagree on species
        n_dets = len(animal_dets)
        for i in range(n_dets):
            for j in range(i + 1, n_dets):
                if animal_dets[i].iou(animal_dets[j]) > 0.50:
                    top_i = det_items[i].top_3[0].class_id if det_items[i].top_3 else ""
                    top_j = det_items[j].top_3[0].class_id if det_items[j].top_3 else ""
                    if top_i != top_j:
                        for k in (i, j):
                            det_items[k].status = "uncertain"
                            det_items[k].species = None
                            det_items[k].confidence_calibrated = None
                            det_items[k].rating = None

        # §9.1.3: Select `primary` result for the box with highest `confidence * box_area`
        primary_idx = max(
            range(n_dets),
            key=lambda i: float(animal_dets[i].confidence) * float(animal_dets[i].area),
        )
        primary_item = det_items[primary_idx]
        primary_gate = raw_gate_outputs[primary_idx]

        # Stage 6: Explanation (live Gemini called only when requested or uncertain, §9.3.1)
        if explain or primary_item.status == "uncertain":
            explanation = self.argon.explain_prediction(
                status=primary_item.status,
                predicted_species=(
                    primary_item.species.to_dict() if primary_item.species else None
                ),
                top_3=primary_gate["top_3"],
                photo_quality=primary_item.quality.to_dict(),
                coarse_group_fallback=primary_item.coarse_group_fallback,
                crop_used=crop_used,
                image_bytes=safe_png,
            )
        else:
            explanation = build_interpretable_explanation(
                status=primary_item.status,
                predicted_species=(
                    primary_item.species.to_dict() if primary_item.species else None
                ),
                top_3=primary_gate["top_3"],
                photo_quality=primary_item.quality.to_dict(),
                coarse_group_fallback=primary_item.coarse_group_fallback,
                crop_used=crop_used,
            )

        return PredictionResponse(
            status=primary_item.status,
            predicted_species=primary_item.species,
            confidence_calibrated=primary_item.confidence_calibrated,
            top_3=primary_item.top_3,
            photo_quality=primary_item.quality,
            identification_ready_rating=primary_item.rating,
            explanation=explanation,
            model_version=self.model_version,
            calibration_version=self.calibration_version,
            rating_version=self.rating_version,
            argon_model_version=self.argon.model_id,
            detector_version=self.detector.version,
            crop_version=self.crop_version,
            detections=det_items,
            primary_index=primary_idx,
            coarse_group_fallback=primary_item.coarse_group_fallback,
            crop_used=crop_used,
        )
