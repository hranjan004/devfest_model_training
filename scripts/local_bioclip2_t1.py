#!/usr/bin/env python3
"""Train a BioCLIP 2 T1 linear-probe head locally (Apple MPS / CUDA / CPU) from the committed split_v2.

Unlike `colab_auto_train.py`, this runs on a laptop and only uses the photos already listed in
`data/splits/split_v2.csv` (262 train / 40 val / 40 test). It writes the head that the serving
backend (`wildlife.models.bioclip2_serving`) loads:

    runs/bioclip2_local_t1/bioclip2_linear_head.npz   (weights [20,768], bias [20], class_ids)
    runs/bioclip2_local_t1/metrics.json               (T0 zero-shot + T1 test metrics)

Whole images are embedded (no detector crops), so numbers are not comparable to the crop-v1 Colab run.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import io
import json
from pathlib import Path
import sys
import urllib.request

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from wildlife.models.backbones import build_bioclip2_zero_shot_prompts  # noqa: E402
from wildlife.schemas import load_species_taxonomy  # noqa: E402

S3 = "https://inaturalist-open-data.s3.amazonaws.com/photos/{pid}/medium.{ext}"


def fetch(pid: int, cache: Path) -> Path | None:
    out = cache / f"{pid}.jpg"
    if out.exists() and out.stat().st_size > 0:
        return out
    for ext in ("jpg", "jpeg", "png"):
        try:
            with urllib.request.urlopen(S3.format(pid=pid, ext=ext), timeout=20) as r:
                out.write_bytes(r.read())
                return out
        except Exception:
            continue
    return None


def macro_f1(y: np.ndarray, p: np.ndarray, n: int) -> float:
    f1s = []
    for c in range(n):
        tp = int(((p == c) & (y == c)).sum())
        fp = int(((p == c) & (y != c)).sum())
        fn = int(((p != c) & (y == c)).sum())
        if tp + fp + fn == 0:
            continue
        f1s.append(0.0 if tp == 0 else 2 * tp / (2 * tp + fp + fn))
    return float(np.mean(f1s))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", type=Path, default=ROOT / "runs" / "bioclip2_local_t1")
    ap.add_argument("--cache", type=Path, default=ROOT / "data" / "cache" / "medium")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    args.cache.mkdir(parents=True, exist_ok=True)

    import open_clip
    import torch
    from PIL import Image
    from sklearn.linear_model import LogisticRegression

    species = load_species_taxonomy()
    class_ids = [s.class_id for s in species]
    idx = {c: i for i, c in enumerate(class_ids)}

    split = pd.read_csv(ROOT / "data" / "splits" / "split_v2.csv")
    attr = pd.read_csv(ROOT / "data" / "manifests" / "photo_attribution_v2.csv")
    df = split.merge(attr[["image_id", "photo_id"]], on="image_id")
    df = df[df.class_id.isin(class_ids)].reset_index(drop=True)

    with ThreadPoolExecutor(16) as ex:
        paths = list(ex.map(lambda pid: fetch(int(pid), args.cache), df.photo_id))
    df["path"] = paths
    missing = int(df.path.isna().sum())
    df = df.dropna(subset=["path"]).reset_index(drop=True)
    print(f"images: {len(df)} (missing {missing})")

    device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
    model, _, preprocess = open_clip.create_model_and_transforms("hf-hub:imageomics/bioclip-2")
    model = model.to(device).eval()
    tok = open_clip.get_tokenizer("hf-hub:imageomics/bioclip-2")

    @torch.no_grad()
    def embed(paths: list[Path]) -> np.ndarray:
        out = []
        for i in range(0, len(paths), 16):
            batch = torch.stack([preprocess(Image.open(p).convert("RGB")) for p in paths[i : i + 16]]).to(device)
            f = model.encode_image(batch)
            out.append(torch.nn.functional.normalize(f, dim=-1).float().cpu().numpy())
        return np.concatenate(out)

    @torch.no_grad()
    def text_matrix() -> np.ndarray:
        prompts = build_bioclip2_zero_shot_prompts()
        rows = []
        for c in class_ids:
            t = model.encode_text(tok(prompts[c]).to(device))
            t = torch.nn.functional.normalize(t, dim=-1).mean(0)
            rows.append(torch.nn.functional.normalize(t, dim=-1).float().cpu().numpy())
        return np.stack(rows)

    X = embed(list(df.path))
    y = df.class_id.map(idx).to_numpy()
    tr = df.split.isin(["train", "validation"]).to_numpy()
    te = (df.split == "test").to_numpy()

    T = text_matrix()
    zs_pred = (X[te] @ T.T).argmax(1)
    t0 = {"macro_f1": macro_f1(y[te], zs_pred, 20), "top1": float((zs_pred == y[te]).mean())}

    clf = LogisticRegression(C=10.0, max_iter=5000)
    clf.fit(X[tr], y[tr])
    logits = clf.decision_function(X[te])
    pred = logits.argmax(1)
    top3 = float(np.mean([y[te][i] in np.argsort(-logits[i])[:3] for i in range(len(pred))]))
    t1 = {"macro_f1": macro_f1(y[te], pred, 20), "top1": float((pred == y[te]).mean()), "top3": top3}

    np.savez(
        args.out / "bioclip2_linear_head.npz",
        weights=clf.coef_.astype(np.float32),
        bias=clf.intercept_.astype(np.float32),
        class_ids=np.array(class_ids),
        text_matrix=T.astype(np.float32),
    )
    metrics = {
        "backbone": "hf-hub:imageomics/bioclip-2",
        "input": "whole image (no detector crop)",
        "train_images": int(tr.sum()),
        "test_images": int(te.sum()),
        "t0_zero_shot_test": t0,
        "t1_linear_probe_test": t1,
        "device": device,
    }
    (args.out / "metrics.json").write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
