// Mirrors src/wildlife/schemas.py PredictionResponse.to_v2_dict() on main.

export type Group = 'large_mammal' | 'small_mammal' | 'bird'
export type Status = 'identified' | 'uncertain' | 'unsupported' | 'no_animal'

export interface Species {
  class_id: string
  index: number
  common_name: string
  scientific_name: string
  group: Group
  campus_habitat: string
}

export interface TopCandidate {
  class_id: string
  probability: number
  common_name?: string
  scientific_name?: string
}

export interface Quality {
  overall: number
  sharpness: number
  visibility: number
  exposure: number
  resolution: number
  composition: number
}

export interface Detection {
  box: [number, number, number, number] // x1, y1, x2, y2 in original-image pixels
  box_source: 'megadetector_v6' | 'owlv2' | 'manual' | string
  detector_confidence: number
  status: Status
  species: { class_id: string; common_name: string; scientific_name: string; group: Group } | null
  confidence_calibrated: number | null
  top_3: TopCandidate[]
  quality: Quality
  rating: number | null
  coarse_group_fallback?: string
}

export interface PredictionV2 {
  status: Status
  detections: Detection[]
  primary_index: number | null
  primary: Detection | null
  detector_version: string
  crop_version: string
  model_version: string
  explanation?: string
  note?: string | null
  /** set on seed posts: the date their prediction was recorded from the live API */
  recorded_on?: string
}

export interface Comment {
  id: string
  author: string
  text: string
  at: string
}

export interface Post {
  id: string
  image: string
  width: number
  height: number
  author: string
  attribution?: string
  source?: string
  observed_on: string
  place: string
  lat: number
  lng: number
  prediction: PredictionV2
  likes: number
  liked: boolean
  comments: Comment[]
  /** true for seeded demo posts whose scores are samples, not model output */
  sample: boolean
}
