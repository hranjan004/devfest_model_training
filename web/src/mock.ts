import { SPECIES } from './data/species'
import type { Detection, PredictionV2, Quality } from './types'

/** Deterministic pseudo-random numbers from a string seed. */
export function seeded(seed: string) {
  let h = 2166136261
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 16777619)
  return () => {
    h = Math.imul(h ^ (h >>> 15), 2246822507)
    h = Math.imul(h ^ (h >>> 13), 3266489909)
    return ((h ^= h >>> 16) >>> 0) / 4294967296
  }
}

function quality(rand: () => number): Quality {
  const c = () => Math.round(55 + rand() * 43)
  const q = { sharpness: c(), visibility: c(), exposure: c(), resolution: c(), composition: c() }
  const overall = Math.round(0.3 * q.sharpness + 0.25 * q.visibility + 0.15 * q.exposure + 0.15 * q.resolution + 0.15 * q.composition)
  return { overall, ...q }
}

/** Sample detection with the same shape as the real pipeline. */
export function sampleDetection(classId: string, width: number, height: number, seed: string, centred = false): Detection {
  const rand = seeded(seed)
  const sp = SPECIES.find((s) => s.class_id === classId) ?? SPECIES[0]
  // Seed photos are usually framed on the animal, so their sample box sits centred and large.
  const bw = width * (centred ? 0.62 + rand() * 0.12 : 0.35 + rand() * 0.3)
  const bh = height * (centred ? 0.62 + rand() * 0.12 : 0.35 + rand() * 0.3)
  const x1 = (width - bw) * (centred ? 0.5 : 0.25 + rand() * 0.5)
  const y1 = (height - bh) * (centred ? 0.5 : 0.3 + rand() * 0.4)
  const p1 = 0.78 + rand() * 0.2
  const others = SPECIES.filter((s) => s.class_id !== sp.class_id && s.group === sp.group)
  const o1 = others[Math.floor(rand() * others.length)]
  const o2 = others.find((s) => s !== o1) ?? others[0]
  const rest = 1 - p1
  const q = quality(rand)
  return {
    box: [Math.round(x1), Math.round(y1), Math.round(x1 + bw), Math.round(y1 + bh)],
    box_source: 'megadetector_v6',
    detector_confidence: +(0.7 + rand() * 0.29).toFixed(2),
    status: 'identified',
    species: { class_id: sp.class_id, common_name: sp.common_name, scientific_name: sp.scientific_name, group: sp.group },
    confidence_calibrated: +p1.toFixed(4),
    top_3: [
      { class_id: sp.class_id, probability: +p1.toFixed(4), common_name: sp.common_name },
      { class_id: o1.class_id, probability: +(rest * 0.7).toFixed(4), common_name: o1.common_name },
      { class_id: o2.class_id, probability: +(rest * 0.2).toFixed(4), common_name: o2.common_name },
    ],
    quality: q,
    rating: Math.round(0.65 * q.overall + 0.35 * 100 * p1),
  }
}

export function wrap(det: Detection): PredictionV2 {
  return {
    status: det.status,
    detections: [det],
    primary_index: 0,
    primary: det,
    detector_version: 'md6-apa-rtdetr-e@apache2.0',
    crop_version: 'crop-v1',
    model_version: 'demo',
  }
}

/**
 * Offline stand-in for /v2/predict. It cannot recognize anything; it returns a
 * random species so the UI flow can be exercised. Every result it produces is
 * labelled "Demo result" in the UI.
 */
export async function demoPredict(file: File, dims: { width: number; height: number }): Promise<PredictionV2> {
  await new Promise((r) => setTimeout(r, 900))
  const seed = `${file.name}:${file.size}`
  const rand = seeded(seed)
  const pick = SPECIES[Math.floor(rand() * SPECIES.length)]
  const det = sampleDetection(pick.class_id, dims.width, dims.height, seed)
  // Every fourth photo exercises the "uncertain" path with a group rollup.
  if (rand() < 0.25) {
    det.status = 'uncertain'
    det.confidence_calibrated = 0.46
    det.top_3[0].probability = 0.46
    det.top_3[1].probability = 0.31
    det.rating = null
    det.coarse_group_fallback = pick.group
  }
  return { ...wrap(det), model_version: 'demo' }
}
