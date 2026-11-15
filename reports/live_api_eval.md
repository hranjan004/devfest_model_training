# Live `/v2/predict` check: real MegaDetector V6 + BioCLIP 2 (local T1 head)

Run on 2026-11-14 on an Apple M5 Pro (MPS), `uvicorn api.main:app` with
`WILDLIFE_TEST_MODE=0 WILDLIFE_BIOCLIP2_HEAD=runs/bioclip2_local_t1/bioclip2_linear_head.npz`.

## Why this was needed

Before this change `/v2/predict` never ran BioCLIP 2. `wildlife.train --tier t1` saves an untrained numpy
`WildlifeClassifier` stub as `best.ckpt` and writes the real head to `bioclip2_linear_head.npz`, which no
serving code loaded. `src/wildlife/models/bioclip2_serving.py` now loads that head; the pipeline calls
`forward_logits_rgb` on the 512px detector crop.

## Head used

`scripts/local_bioclip2_t1.py`: BioCLIP 2 ViT-L/14 embeddings of whole images from the committed
`split_v2.csv` (302 train+val photos, about 15 per species), LogisticRegression C=10.
On the 40-photo test split: T0 zero-shot top-1 0.95, T1 top-1 1.00. With 2 test photos per species
these numbers are noisy; they show the model works, not how well it generalises.

## Live results (50 requests, median 0.48 s each after warm-up)

| Set | n | Result |
|---|---|---|
| UCSC seed photos (iNat CC0/CC-BY, not in training) | 40 | 14 `identified`, all correct; 24 `uncertain`; 2 `no_animal` (detector missed) |
| Same 40, top-1 of `top_3` regardless of status | 40 | 37 correct, 1 wrong (a Striped skunk photo read as Common raven at p 0.32, still `uncertain`), 2 no box |
| OOD species from `ood_test` (fox squirrel, blue jay, puma, ...) | 9 | 9 `uncertain`, none mislabelled as a campus species |
| Synthetic blank gradient | 1 | `uncertain`: MegaDetector returned a full-frame box at ≥ 0.25 |

## What this means

- The classifier is right; the gate is strict. Correct predictions often land at p 0.5 to 0.77, under
  `max_prob_threshold: 0.78` in `configs/rating.yaml`, so they show as `uncertain`. The serving temperature is
  1.0 because no temperature was fitted for this head. Fitting T on a real validation set (Harsh's
  3,000-image Colab run) should move most of these to `identified` without touching OOD rejection.
- Ask Harsh for `runs/classifier_v2_t1/bioclip2_linear_head.npz` from the Colab run; it drops in with
  `WILDLIFE_BIOCLIP2_HEAD`. Its training images were whole images, as here, not detector crops.
- MegaDetector's first-call lazy load hung inside FastAPI's worker thread; it now loads at startup.
