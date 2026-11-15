# coy architecture

## Native app

The SwiftUI iOS 18+ app lives in `ios/ucscdevfestapp`. Home, Species, Identify, Ranked, and Map share `SightingStore`. Models decode the 34-class catalog and prediction metadata. `IdentifyView` sends a JPEG stripped of photo metadata through `WildlifeAPI`, presents the real prediction and photo-quality scores, and collects a custom name, notes, and a marked location. Apple MapKit renders the location picker and searchable named sightings; selecting a map preview opens the same detail view used by Home and Ranked.

`SightingStore` loads 40 original historical records and 21 named records imported from the earlier app. The app includes 34 reference photos, source links, and attribution. These seed records retain recorded prediction metadata and are not new live inference requests. Names such as Deerly and Whiskers are demo labels, and imported locations are approximate. A map pin does not imply an animal's current position or a movement route.

New posts, JPEGs, comments, likes, names, and coordinates are stored in the app's local Documents directory. Optional new fields decode older saved records. Reopening the app retains local data. Deleting the app deletes that installation's data. There is no account or cross-device synchronization in this client.

## Real inference path

```text
iPhone / simulator
  POST photo → coy bridge :8081 /v2/predict
                  POST original bytes → model API :8080 /v3/identify
                                          BioCLIP 2 + trained v4 adapter
                  ← validated class, confidence, alternatives
  ← native response schema + photo-quality heuristics
```

`api/coy_bridge.py` is an adapter, not a classifier. It requires the 34-class catalog and validates the upstream model version, response classes, and probabilities. Missing model files or an unavailable upstream produce an error; no prediction is fabricated. The bridge's v2-shaped route is distinct from the old v2 pipeline on port 8080.

The current model performs **whole-photo classification**, without an animal detector. The response uses a full-image region only for schema compatibility and declares `none-whole-image`; the app does not draw a fabricated detected box. Photo quality is heuristic (sharpness, exposure, resolution, visibility, composition), and the composite photo rating combines quality with identification confidence. A rating of 91 is not 91% species confidence.

The trained run is loaded by `src/wildlife/models/ucsc34.py`. The adapter includes the trained head and fine-tuned transformer blocks; the pinned BioCLIP 2 base model comes from Hugging Face. Required run files are `model_adapter.pt`, `model_checksum.json`, `classes.json`, and `ucsc_bioclip.json`. They remain gitignored. Training and calibration details and held-out results are in [DATASETS.md](DATASETS.md); the model has 34 closed-set labels and is not an exhaustive unknown-species detector.

## Local runtime and transport

`scripts/run_coy.sh` validates the environment, reuses a healthy trained API when available, or starts it on loopback port 8080. The app bridge listens on port 8081 (LAN by default). On exit the launcher stops only its own child processes. It performs no database reset, seeding, or package installation.

The simulator uses localhost:8081. A real iPhone uses the Mac's reachable Wi-Fi address:8081; USB-C pairing does not forward phone localhost to the Mac. Debug includes a local-network purpose string and permits the local HTTP development service. Release has no blanket arbitrary-load exception. This unauthenticated development service should stay on a trusted local network; production needs HTTPS and a separate authentication/storage design. See [IPHONE_SETUP.md](IPHONE_SETUP.md).

## Existing legacy backend

`api/v3.py` and `api/store.py` still provide SQLite-backed sighting/rating/comment endpoints for the older app and integrations. The current coy client uses v3 only indirectly for classification and **does not publish its posts to that SQLite service**. Earlier v1/v2 detector and classification experiments remain for training continuity; synthetic smoke-test outputs are not used by the live coy bridge.

## Tests

Bridge tests cover all 34 class mappings, unchanged confidence and upload bytes, health, input validation, low confidence, and upstream errors without downloading weights. Native tests cover catalog/resource integrity, prediction handling, and migration/persistence. `CoyDemoTests` exercises a real model upload, named marked post, map detail, comment, and reopening. `CoyRankedDemoTests` browses large mammals and locates Deerly and Whiskers on the map. Physical-device signing requires validation on the owner's phone.
