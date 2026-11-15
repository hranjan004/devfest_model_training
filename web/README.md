# Campus Wildlife web app

React 19 + TypeScript + Vite + Tailwind v4 front end for the UCSC Wildlife Vision API.
It follows the team's Figma wireframes (Home feed, View post, Species, Rankings) and
adds the Identify flow the wireframes were missing: photo → detector boxes →
species + top‑3 + photo quality → confirm or correct → post.

## Run

```bash
cd web
npm install
npm run dev          # http://localhost:5173
```

Requests to `/v1/*`, `/v2/*` and `/healthz` are proxied to the FastAPI service on
`http://localhost:8000` (`api/main.py`).

### Real models (MegaDetector V6 + BioCLIP 2)

Plain `uvicorn api.main:app` runs the test-mode stubs. For real predictions you need
torch, `open_clip_torch` and `PytorchWildlife` (Python 3.10+), plus a BioCLIP 2 linear
head. From the repo root:

```bash
uv venv .venv-ml --python 3.12
VIRTUAL_ENV=.venv-ml uv pip install torch torchvision open_clip_torch==2.26.1 scikit-learn \
  fastapi uvicorn python-multipart pillow numpy pandas pyyaml requests PytorchWildlife \
  soundfile librosa "setuptools<81"
.venv-ml/bin/python scripts/local_bioclip2_t1.py          # trains runs/bioclip2_local_t1/ (~2 min on MPS)
WILDLIFE_TEST_MODE=0 WILDLIFE_BIOCLIP2_HEAD=runs/bioclip2_local_t1/bioclip2_linear_head.npz \
  .venv-ml/bin/uvicorn api.main:app --port 8000
```

The first start downloads BioCLIP 2 (~1.7 GB) and MegaDetector V6 (~1.2 GB).
`reports/live_api_eval.md` has the results of a 50-photo check against this setup.
The Field station panel on the home page shows whether the API is live.

When the API isn't reachable, Identify falls back to an in-browser **demo predictor**
that picks a random species. Every demo result is labelled as such in the UI.

## Data and honesty rules

- Seed posts are real CC0 / CC‑BY research‑grade iNaturalist observations near campus
  (`scripts/fetch_seed_photos.py` → `src/data/seed.json`), credited to each observer.
  Their boxes, confidence, top-3 and rating are real `/v2/predict` output recorded by
  `scripts/record_seed_predictions.py`, and each post says which model and date.
  That script also coarsens `place` so no observer's street address is shown.
- Locations are rounded to ~1 km and drawn as a circle, never a pin.
- Uploaded photos are re‑encoded through a canvas, which drops EXIF/GPS.
- Corrections go to `POST /v1/feedback` (review queue only, `consent: true`), never
  straight into training data.

## Structure

```
src/types.ts          v2 response types, mirroring schemas.py to_v2_dict()
src/api.ts            /v2/predict and /v1/feedback, demo fallback
src/mock.ts           demo predictor and sample detections
src/store.tsx         posts, likes, comments (localStorage for your own posts)
src/components.tsx    side rail, tab bar, DetectionPhoto (lock-on brackets), group chips, result widgets
src/pages/            Feed (+ FieldStation rail), PostView, Species, Rankings, Identify
src/index.css         tokens: palette, group colours, type scale (t-display/t-title/t-heading/t-meta), motion
```

## Design

The Claude Design canvas with the desktop home, phone Identify result and token sheet is
the reference for these screens. Rules the code follows:

- One signal colour: slug yellow brackets mean the model named the animal; white means
  it isn't sure; lichen means not one of the 20 species.
- Group colours (large mammals redwood, small mammals ochre, birds estuary blue) appear
  only as dots, bars and chip tints, always next to a text label.
- Bricolage Grotesque (condensed, 80–85% width) for headings and numbers, Atkinson
  Hyperlegible for everything else, through the four `t-*` utilities only.
- One orchestrated motion: lock-on (brackets close onto the detector box, then the tag
  and confidence bars fill). Everything respects `prefers-reduced-motion`.

