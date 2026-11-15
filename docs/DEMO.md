# coy demo

[Watch the 90-second MP4](../coy_product_demo.mp4) · [Full photo credits](../coy_product_demo_credits.md)

This is a real native iOS simulator recording, not a mockup. The 1920×1080, 30 fps, silent edit centers the phone on a light background. Short black one-line feature introductions precede each feature; the native footage is trimmed, lightly retimed, and cross-dissolved.

| Approximate time | Feature |
|---|---|
| 0–16s | coy introduction, Home, and Sammy's named map pin |
| 16–27s | Choose a photo and receive a real banana-slug result, displayed as 99.6% |
| 27–44s | Name Goldie, add notes, mark a campus spot, publish, and view its map entry |
| 44–56s | Open Goldie's detail and add a comment |
| 56–74s | Ranked large mammals, Deerly, Whiskers, and a brief Bobcat view |
| 74–86s | Locate Deerly and Whiskers on the map |
| 86–90s | coy closing card |

The upload is Anne Parsons' CC0 iNaturalist banana-slug photo, observation 9631092, photo 13149165, taken from the existing licensed DEVFEST sample. The photo's license was checked through the iNaturalist API. Its marked campus point is illustrative. Other photo credits and links are in the accompanying credit file and native detail screens. Deerly and Whiskers are historical seeded demo entries, with approximate locations; their prerecorded predictions are distinguished in the app from the live Goldie upload.

## Verified behavior

- The real `ucsc34-bioclip2-v4` service returned class I01, Banana slug (genus), confidence 0.995834 (rounded to 99.6% in the app).
- Goldie's name, notes, marked coordinates, image, and comment were saved and survived relaunch. These are local device records, not a claim of server or cross-user publication.
- Native catalog/storage tests passed. Both the named-post and ranked/map UI flows passed on iOS 18.3.1.
- The extended video includes Ranked and both Deerly and Whiskers map selections. Existing app data was not erased for the recordings.
- USB-C installation on a physical iPhone was documented, not performed. See [the iPhone guide](IPHONE_SETUP.md).

## Reproduce a recording

Start the trained services using `bash scripts/run_coy.sh`, then run `bash scripts/capture_demo.sh`. The capture helper creates a new dated iPhone simulator, imports the CC0 sample, builds the app, and records `CoyDemoTests` followed by `CoyRankedDemoTests`. It saves raw videos and test logs under gitignored `data/app/coy-captures/`. It never erases a simulator or deletes sightings. The named flow creates a local Goldie post and comment. Existing devices can be selected explicitly with `DEMO_DEVICE=<UDID>`, but the photo picker assumes the sample is the first photo, so the default new simulator is recommended.

The helper records native footage; marketing cards, framing, timing, and dissolves are editorial additions. Older images and recordings under `docs/demo/` document the prior app and remain for history; the root `coy_product_demo.mp4` is the current demo.
