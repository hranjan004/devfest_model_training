import { createContext, useContext, useEffect, useMemo, useReducer, type ReactNode } from 'react'
import seed from './data/seed.json'
import { sampleDetection, seeded, wrap } from './mock'
import type { Comment, Post, PredictionV2 } from './types'

interface SeedPhoto {
  id: string
  class_id: string
  image: string
  attribution: string
  source: string
  observed_on: string
  lat: number
  lng: number
  place: string
  observer: string
  width?: number
  height?: number
  /** real /v2/predict output recorded by web/scripts/record_seed_predictions.py */
  prediction?: PredictionV2
}

const NOMINAL = 1000 // fallback sample boxes are expressed on a 1000×1000 canvas

function seedPosts(): Post[] {
  return (seed as SeedPhoto[]).map((s) => {
    const rand = seeded(s.id)
    const author = s.observer
    const real = s.prediction && s.width && s.height
    return {
      id: s.id,
      image: s.image,
      width: real ? s.width! : NOMINAL,
      height: real ? s.height! : NOMINAL,
      author,
      attribution: s.attribution,
      source: s.source,
      observed_on: s.observed_on,
      place: s.place,
      lat: s.lat,
      lng: s.lng,
      prediction: real ? s.prediction! : wrap(sampleDetection(s.class_id, NOMINAL, NOMINAL, s.id, true)),
      likes: Math.floor(rand() * 60),
      liked: false,
      comments: [],
      sample: !real,
    }
  })
}

type Action =
  | { type: 'add'; post: Post }
  | { type: 'like'; id: string }
  | { type: 'comment'; id: string; comment: Comment }

interface Saved {
  mine: Post[]
  liked: string[]
  comments: Record<string, Comment[]>
}

const KEY = 'ucsc-wildlife:v1'

function load(): Saved {
  try {
    const raw = localStorage.getItem(KEY)
    if (raw) return JSON.parse(raw) as Saved
  } catch {
    /* storage blocked or corrupt: start fresh */
  }
  return { mine: [], liked: [], comments: {} }
}

/** The user's own posts; everything else is a seed post rebuilt from seed.json on load. */
const isMine = (p: Pick<Post, 'id'>) => p.id.startsWith('mine-')

function init(): Post[] {
  const saved = load()
  return [...saved.mine.filter(isMine), ...seedPosts()].map((p) => ({
    ...p,
    liked: saved.liked.includes(p.id),
    likes: p.likes + (saved.liked.includes(p.id) && !isMine(p) ? 1 : 0),
    comments: isMine(p) ? p.comments : saved.comments[p.id] ?? [],
  }))
}

function reducer(posts: Post[], a: Action): Post[] {
  switch (a.type) {
    case 'add':
      return [a.post, ...posts]
    case 'like':
      return posts.map((p) => (p.id === a.id ? { ...p, liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1) } : p))
    case 'comment':
      return posts.map((p) => (p.id === a.id ? { ...p, comments: [...p.comments, a.comment] } : p))
  }
}

const Ctx = createContext<{ posts: Post[]; dispatch: (a: Action) => void } | null>(null)

export function StoreProvider({ children }: { children: ReactNode }) {
  const [posts, dispatch] = useReducer(reducer, undefined, init)
  useEffect(() => {
    const saved: Saved = {
      mine: posts.filter(isMine),
      liked: posts.filter((p) => p.liked).map((p) => p.id),
      comments: Object.fromEntries(posts.filter((p) => !isMine(p) && p.comments.length).map((p) => [p.id, p.comments])),
    }
    try {
      localStorage.setItem(KEY, JSON.stringify(saved))
    } catch {
      /* quota or blocked storage: keep working in memory */
    }
  }, [posts])
  const value = useMemo(() => ({ posts, dispatch }), [posts])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useStore outside StoreProvider')
  return v
}

export function primaryOf(p: Post) {
  return p.prediction.primary ?? p.prediction.detections[0] ?? null
}
