# Datasets

All training and evaluation images come from [iNaturalist](https://www.inaturalist.org), a community science platform where people upload photos of organisms and other users confirm the identification. Only photos their owners licensed as **CC0** or **CC BY** were used. No images are stored in this repository. They stay in the training folder on Google Drive, and every image is recorded with its photographer, license, and source URL so it can be credited and traced.

## 34-class dataset (current model)

This is the dataset behind `runs/ucsc34_bioclip_v4/` and the app. It was built and used in [`notebooks/12_UCSC_34_CLASSES_BUGS_SLUGS_TREES_GPU.ipynb`](../notebooks/12_UCSC_34_CLASSES_BUGS_SLUGS_TREES_GPU.ipynb), which runs on a Google Colab GPU.

### How the images were collected

1. **Taxon lookup.** Each class name is resolved through the iNaturalist taxa API to an exact, active taxon (the most observed one when names repeat). Black-tailed deer is resolved at the subspecies *Odocoileus hemionus columbianus*. Banana slug is resolved at the genus *Ariolimax*.
2. **Observation filter.** The notebook requests observations that are research grade (the community agrees on the species), verifiable, have photos, and have at least one CC0 or CC BY photo. It also checks that each observation's taxon is the requested taxon or one of its descendants.
3. **California first.** Observations from California (iNaturalist place 14) are used first. If California cannot fill a class, the search widens to observations anywhere.
4. **Photo filter.** Photos are downloaded at iNaturalist's "large" size. Photos smaller than 224 pixels on the short side, or larger than 20 MB, are rejected.
5. **Duplicates.** A photo is rejected if its SHA-256 matches an accepted photo, or if its perceptual hash is within a Hamming distance of 4 of one (checked with a BK-tree). More than one photo per observation is allowed when the photos are distinct.
6. **Targets.** 1,000 photos per class, except banana slug at 358. If any class falls short, the notebook stops before training.
7. **Rate limits.** API calls are spaced at least 1.1 seconds apart and media downloads stay within iNaturalist's daily limits.

Total: 33 classes x 1,000 + 358 banana slug = **33,358 images**. The manifest hash is recorded in `runs/ucsc34_bioclip_v4/dataset_identity.json` (`5c21e7d6…89c8`).

### Splits

Images are split by **photographer**, so no photographer appears in more than one split. This stops the model from scoring well by recognising one person's camera, backgrounds, or habits. Rows are assigned to 10 folds with scikit-learn's `StratifiedGroupKFold` (stratified by class, grouped by iNaturalist user id).

| Split | Folds | Share | Used for |
|---|---|---:|---|
| Train | 6 | about 60% | Fitting the model |
| Validation | 1 | about 10% | Early stopping and checkpoint choice (macro-F1) |
| Calibration | 1 | about 10% | Fitting the temperature for calibrated probabilities |
| Test | 2 | about 20% | Final numbers only (6,267 images) |

### Classes

| ID | Common name | Scientific name | Group | iNat taxon | Test F1 |
|---|---|---|---|---:|---:|
| M01 | Black-tailed deer | *Odocoileus hemionus* (ssp. *columbianus*) | Large mammal | [42221](https://www.inaturalist.org/taxa/42221) | 0.961 |
| M02 | Coyote | *Canis latrans* | Large mammal | [42051](https://www.inaturalist.org/taxa/42051) | 0.886 |
| M03 | Bobcat | *Lynx rufus* | Large mammal | [41976](https://www.inaturalist.org/taxa/41976) | 0.878 |
| M04 | Gray fox | *Urocyon cinereoargenteus* | Large mammal | [42076](https://www.inaturalist.org/taxa/42076) | 0.824 |
| M05 | Northern raccoon | *Procyon lotor* | Small mammal | [41663](https://www.inaturalist.org/taxa/41663) | 0.884 |
| M06 | Striped skunk | *Mephitis mephitis* | Small mammal | [41880](https://www.inaturalist.org/taxa/41880) | 0.929 |
| M07 | California ground squirrel | *Otospermophilus beecheyi* | Small mammal | [180007](https://www.inaturalist.org/taxa/180007) | 0.970 |
| M08 | Eastern gray squirrel | *Sciurus carolinensis* | Small mammal | [46017](https://www.inaturalist.org/taxa/46017) | 0.902 |
| M09 | Western gray squirrel | *Sciurus griseus* | Small mammal | [46023](https://www.inaturalist.org/taxa/46023) | 0.963 |
| M10 | Brush rabbit | *Sylvilagus bachmani* | Small mammal | [43112](https://www.inaturalist.org/taxa/43112) | 0.990 |
| B01 | Wild turkey | *Meleagris gallopavo* | Bird | [906](https://www.inaturalist.org/taxa/906) | 0.964 |
| B02 | California quail | *Callipepla californica* | Bird | [1409](https://www.inaturalist.org/taxa/1409) | 0.949 |
| B03 | Steller's jay | *Cyanocitta stelleri* | Bird | [8234](https://www.inaturalist.org/taxa/8234) | 0.959 |
| B04 | California scrub-jay | *Aphelocoma californica* | Bird | [506118](https://www.inaturalist.org/taxa/506118) | 0.966 |
| B05 | Common raven | *Corvus corax* | Bird | [8010](https://www.inaturalist.org/taxa/8010) | 0.900 |
| B06 | Acorn woodpecker | *Melanerpes formicivorus* | Bird | [18209](https://www.inaturalist.org/taxa/18209) | 0.970 |
| B07 | Anna's hummingbird | *Calypte anna* | Bird | [6317](https://www.inaturalist.org/taxa/6317) | 0.919 |
| B08 | American robin | *Turdus migratorius* | Bird | [12727](https://www.inaturalist.org/taxa/12727) | 0.958 |
| B09 | Dark-eyed junco | *Junco hyemalis* | Bird | [10094](https://www.inaturalist.org/taxa/10094) | 0.965 |
| B10 | Spotted towhee | *Pipilo maculatus* | Bird | [9420](https://www.inaturalist.org/taxa/9420) | 0.940 |
| I01 | Banana slug (genus) | *Ariolimax* | Gastropod | [47777](https://www.inaturalist.org/taxa/47777) | 1.000 |
| T01 | Coast redwood | *Sequoia sempervirens* | Tree | [47372](https://www.inaturalist.org/taxa/47372) | 0.973 |
| T02 | Douglas-fir | *Pseudotsuga menziesii* | Tree | [48256](https://www.inaturalist.org/taxa/48256) | 0.968 |
| T03 | Pacific madrone | *Arbutus menziesii* | Tree | [51046](https://www.inaturalist.org/taxa/51046) | 0.965 |
| T04 | Coast live oak | *Quercus agrifolia* | Tree | [1663718](https://www.inaturalist.org/taxa/1663718) | 0.971 |
| T05 | Tanoak | *Notholithocarpus densiflorus* | Tree | [69823](https://www.inaturalist.org/taxa/69823) | 0.959 |
| T06 | California bay | *Umbellularia californica* | Tree | [48807](https://www.inaturalist.org/taxa/48807) | 0.953 |
| T07 | Bigleaf maple | *Acer macrophyllum* | Tree | [48227](https://www.inaturalist.org/taxa/48227) | 0.966 |
| G01 | Monarch butterfly | *Danaus plexippus* | Insect | [48662](https://www.inaturalist.org/taxa/48662) | 0.980 |
| G02 | Western tiger swallowtail | *Papilio rutulus* | Insect | [47226](https://www.inaturalist.org/taxa/47226) | 0.977 |
| G03 | Yellow-faced bumble bee | *Bombus vosnesenskii* | Insect | [57689](https://www.inaturalist.org/taxa/57689) | 0.975 |
| G04 | Yellow-spotted millipede | *Harpaphe haydeniana* | Arthropod | [47737](https://www.inaturalist.org/taxa/47737) | 0.998 |
| G05 | Convergent lady beetle | *Hippodamia convergens* | Insect | [48987](https://www.inaturalist.org/taxa/48987) | 0.990 |
| G06 | Western yellowjacket | *Vespula pensylvanica* | Insect | [61355](https://www.inaturalist.org/taxa/61355) | 0.989 |

The full class records, including the exact query names, are in `runs/ucsc34_bioclip_v4/classes.json`. Per-class precision, recall, and support are in `per_class_test.json`, and the confusion matrix is in `confusion_matrix.json`.

### Things to keep in mind

* **Closed set.** The model was only trained on these 34 classes. A photo of anything else still gets one of the 34 labels, usually with low confidence. The app treats a top probability under 50% as "not sure".
* **Whole photos.** Training used full photos, not crops. Small or distant animals in large scenes are harder.
* **Trees are photographed differently.** Tree photos are often leaves, bark, or whole trees, while animal photos are mostly the animal. Accuracy for trees reflects how iNaturalist users photograph them.
* **Similar species.** The most frequent mistakes on the test set are bobcat taken for coyote (14 of 218) or gray fox (12 of 218), western gray squirrel taken for eastern gray squirrel (12 of 223), and coyote taken for gray fox (9 of 170).
* **Banana slug is smaller.** It has 358 training images instead of 1,000. It still scored 1.000 F1 on its 67 test images, but that test set is small.
* **Geographic mix.** California observations were preferred, but some classes were filled from elsewhere, so the backgrounds are not all Santa Cruz.

## Data used by the app (not for training)

| Data | Where it comes from | Where it lives |
|---|---|---|
| Species reference photos | `scripts/fetch_reference_photos.py` picks one CC0 or CC BY research-grade photo per species, keeping the photo the model is most confident about | `data/app_reference/` (gitignored) with `credits.json` |
| Demo sightings | `scripts/seed_demo_sightings.py` uses research-grade observations within 3 km of campus (15 km as a fallback) that are not location-obscured, and keeps only photos the model labels correctly with at least 50% confidence | `data/app/` (gitignored), flagged `is_demo` |
| User sightings | Photos posted from the app | `data/app/` (gitignored) |

## Earlier 20-species v2 dataset

The earlier two-stage pipeline (detector plus 20-species classifier) used its own pull, described in [`reports/data_card_v2.md`](../reports/data_card_v2.md). Its files are tracked in the repository:

* `data/manifests/manifest_v2.parquet` and `data/manifests/photo_attribution_v2.csv`. 2,940 photos across the 20 species and out-of-distribution taxa (2,078 CC BY, 862 CC0), each with photographer credit and source URL.
* `data/splits/split_v2.csv`. Observer-grouped splits (1,998 train, 426 validation, 426 test, 50 OOD tuning, 40 OOD test).
* `data/manifests/license_audit_v2.json`. The license gate result.

## Licenses

Each image keeps the license its photographer chose on iNaturalist. CC0 images need no credit. CC BY images require credit to the photographer, which is why every manifest row stores the attribution. The BioCLIP 2 base model is MIT licensed. The code in this repository is MIT licensed, as stated in `pyproject.toml`.
