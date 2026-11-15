import { useEffect, useState, type ReactNode } from 'react'
import { BY_ID, GROUP_LABEL, GROUP_ROLLUP } from './data/species'
import { href, type Route } from './router'
import type { Detection, Group, Post, Quality } from './types'

/* ---------- icons (24px, stroke = currentColor) ---------- */
const Svg = ({ children, className = 'size-6' }: { children: ReactNode; className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>
    {children}
  </svg>
)
export const Icon = {
  feed: (c?: string) => <Svg className={c}><path d="M4 10.5 12 4l8 6.5V20h-5v-6H9v6H4z" /></Svg>,
  species: (c?: string) => <Svg className={c}><rect x="4" y="4" width="7" height="7" rx="1.5" /><rect x="13" y="4" width="7" height="7" rx="1.5" /><rect x="4" y="13" width="7" height="7" rx="1.5" /><rect x="13" y="13" width="7" height="7" rx="1.5" /></Svg>,
  rankings: (c?: string) => <Svg className={c}><path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM7 6H4v1a3 3 0 0 0 3 3M17 6h3v1a3 3 0 0 1-3 3" /></Svg>,
  identify: (c?: string) => <Svg className={c}><path d="M4 9V5h4M16 5h4v4M20 15v4h-4M8 19H4v-4" /><circle cx="12" cy="12" r="3" /></Svg>,
  heart: (c?: string, filled?: boolean) => <Svg className={c}><path fill={filled ? 'currentColor' : 'none'} d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z" /></Svg>,
  comment: (c?: string) => <Svg className={c}><path d="M5 18.5V6.5A1.5 1.5 0 0 1 6.5 5h11A1.5 1.5 0 0 1 19 6.5v8a1.5 1.5 0 0 1-1.5 1.5H9z" /></Svg>,
  back: (c?: string) => <Svg className={c}><path d="M15 5l-7 7 7 7" /></Svg>,
  pin: (c?: string) => <Svg className={c}><path d="M12 21s6-5.6 6-11a6 6 0 0 0-12 0c0 5.4 6 11 6 11z" /><circle cx="12" cy="10" r="2" /></Svg>,
  check: (c?: string) => <Svg className={c}><path d="M5 12.5 10 17l9-10" /></Svg>,
}

export function Logo({ className = 'size-7' }: { className?: string }) {
  return (
    <svg viewBox="0 0 28 28" className={className} aria-hidden>
      <rect width="28" height="28" rx="7" fill="var(--color-canopy)" />
      <path d="M7 11V7h4M17 7h4v4M21 17v4h-4M11 21H7v-4" stroke="var(--color-slug)" strokeWidth="2.4" fill="none" />
    </svg>
  )
}

/* ---------- navigation: side rail on desktop, tab bar on phones ---------- */
const TABS = [
  { key: 'feed', label: 'Sightings', to: href.feed, icon: Icon.feed },
  { key: 'species', label: 'Species guide', to: href.species, icon: Icon.species },
  { key: 'rankings', label: 'Best photos', to: href.rankings, icon: Icon.rankings },
] as const

function activeTab(r: Route) {
  if (r.name === 'species' || r.name === 'speciesDetail') return 'species'
  if (r.name === 'rankings') return 'rankings'
  if (r.name === 'identify') return 'identify'
  return 'feed'
}

export function SideNav({ route }: { route: Route }) {
  const cur = activeTab(route)
  return (
    <nav aria-label="Main" className="sticky top-0 hidden h-dvh w-[232px] shrink-0 flex-col gap-7 px-5 py-7 md:flex">
      <a href={href.feed} className="flex items-center gap-2.5">
        <Logo />
        <span className="font-display text-[19px] font-extrabold tracking-tight [font-stretch:85%]">Campus Wildlife</span>
      </a>
      <ul className="flex flex-col gap-1">
        {TABS.map((t) => (
          <li key={t.key}>
            <a
              href={t.to}
              aria-current={cur === t.key ? 'page' : undefined}
              className="flex min-h-11 items-center gap-3 rounded-[10px] px-3.5 text-canopy-soft transition-colors hover:bg-mist hover:text-canopy aria-[current=page]:bg-canopy aria-[current=page]:font-bold aria-[current=page]:text-fog"
            >
              {t.icon('size-5')}
              {t.label}
            </a>
          </li>
        ))}
      </ul>
      <a
        href={href.identify}
        aria-current={cur === 'identify' ? 'page' : undefined}
        className="flex min-h-12 items-center justify-center gap-2.5 rounded-xl bg-redwood font-bold text-white transition-colors hover:bg-redwood-dark"
      >
        <span className="text-slug">{Icon.identify('size-5')}</span>
        Identify an animal
      </a>
    </nav>
  )
}

export function TabBar({ route }: { route: Route }) {
  const cur = activeTab(route)
  const item = (key: string, label: string, to: string, icon: ReactNode) => (
    <a href={to} aria-current={cur === key ? 'page' : undefined} className="flex min-h-14 flex-1 flex-col items-center justify-center gap-0.5 text-[11px] text-canopy-soft aria-[current=page]:font-bold aria-[current=page]:text-canopy">
      {icon}
      {label}
    </a>
  )
  return (
    <nav className="fixed inset-x-0 bottom-0 z-[1000] border-t border-line bg-fog/95 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden" aria-label="Main">
      <div className="flex items-end">
        {item('feed', 'Sightings', href.feed, Icon.feed())}
        {item('species', 'Species', href.species, Icon.species())}
        <a href={href.identify} aria-current={cur === 'identify' ? 'page' : undefined} className="-mt-5 flex flex-1 flex-col items-center gap-0.5 pb-2 text-[11px] font-bold text-redwood">
          <span className="grid size-14 place-items-center rounded-full bg-redwood text-slug shadow-lg ring-4 ring-fog">{Icon.identify('size-7')}</span>
          Identify
        </a>
        {item('rankings', 'Best', href.rankings, Icon.rankings())}
      </div>
    </nav>
  )
}

/* ---------- photo with the detector's brackets ---------- */
const TAG_STYLE: Record<string, string> = {
  identified: 'bg-slug text-canopy',
  uncertain: 'bg-white text-canopy',
  unsupported: 'bg-lichen text-canopy',
}

export function DetectionPhoto({
  post,
  showTags = true,
  animate = false,
  className = '',
  selected,
  onSelect,
}: {
  post: Pick<Post, 'image' | 'width' | 'height' | 'prediction'>
  showTags?: boolean
  animate?: boolean
  className?: string
  selected?: number
  onSelect?: (i: number) => void
}) {
  const { width, height } = post
  // Lock-on: render boxes at the photo edge first, then let them close onto the detector box.
  const [locked, setLocked] = useState(!animate)
  useEffect(() => {
    if (!animate) return
    const id = requestAnimationFrame(() => requestAnimationFrame(() => setLocked(true)))
    return () => cancelAnimationFrame(id)
  }, [animate])

  return (
    <div className={`relative overflow-hidden bg-canopy ${className}`}>
      <img src={post.image} alt={altText(post.prediction.detections)} className="block h-auto w-full" loading="lazy" />
      {post.prediction.detections.map((d, i) => {
        const [x1, y1, x2, y2] = d.box
        const box = { left: `${(x1 / width) * 100}%`, top: `${(y1 / height) * 100}%`, width: `${((x2 - x1) / width) * 100}%`, height: `${((y2 - y1) / height) * 100}%` }
        const edge = { left: '2%', top: '2%', width: '96%', height: '96%' }
        const dim = selected !== undefined && selected !== i
        const Tag = onSelect ? 'button' : 'div'
        const pct = d.status === 'identified' && d.confidence_calibrated != null ? Math.round(d.confidence_calibrated * 100) : null
        // Boxes that hug the top edge get their tag inside the box so it isn't clipped.
        const tagInside = y1 / height < 0.09
        return (
          <Tag
            key={i}
            type={onSelect ? 'button' : undefined}
            onClick={onSelect ? () => onSelect(i) : undefined}
            className={`bracket absolute ${animate ? 'lock' : ''} ${dim ? 'opacity-40' : ''}`}
            data-status={d.status}
            style={locked ? box : edge}
            aria-label={onSelect ? `Show animal ${i + 1}: ${labelOf(d)}` : undefined}
          >
            {showTags && locked && (
              <span className={`absolute inline-flex items-center ${tagInside ? 'top-2 left-2' : '-top-1.5 left-0 -translate-y-full'} gap-1.5 whitespace-nowrap rounded-md px-2 py-0.5 text-[13px] font-bold ${TAG_STYLE[d.status] ?? TAG_STYLE.uncertain} ${animate ? (tagInside ? 'lock-tag-in' : 'lock-tag') : ''}`}>
                {labelOf(d)}
                {pct !== null && <span className="font-normal tabular-nums">{pct}%</span>}
              </span>
            )}
          </Tag>
        )
      })}
    </div>
  )
}

export function topName(d: Detection): string | null {
  const c = d.top_3[0]
  return c ? c.common_name ?? BY_ID[c.class_id]?.common_name ?? null : null
}

export function labelOf(d: Detection): string {
  if (d.status === 'identified' && d.species) return d.species.common_name
  if (d.status === 'uncertain') {
    const name = topName(d)
    if (name) return `Possibly ${name}`
    if (d.coarse_group_fallback) return GROUP_ROLLUP[d.coarse_group_fallback as Group] ?? 'Not sure yet'
    return 'Not sure yet'
  }
  if (d.status === 'unsupported') return 'Not one of the 20 species'
  return 'No animal found'
}

/** The group a detection belongs to: its species, else its best guess. */
export function groupOf(d: Detection | undefined | null): Group | undefined {
  if (!d) return undefined
  if (d.species) return d.species.group
  const c = d.top_3[0]
  return c ? BY_ID[c.class_id]?.group : undefined
}

function altText(ds: Detection[]) {
  if (!ds.length) return 'Photo with no animal detected'
  return `Photo of ${ds.map(labelOf).join(', ')}`
}

/* ---------- groups ---------- */
export const GROUP_COLOR: Record<Group, { dot: string; chip: string }> = {
  large_mammal: { dot: 'bg-large', chip: 'bg-large-tint text-large-ink' },
  small_mammal: { dot: 'bg-small', chip: 'bg-small-tint text-small-ink' },
  bird: { dot: 'bg-bird', chip: 'bg-bird-tint text-bird-ink' },
}

export function GroupChip({ group }: { group?: Group }) {
  if (!group) return null
  const c = GROUP_COLOR[group]
  return (
    <span className={`inline-flex h-[26px] items-center gap-1.5 rounded-full px-2.5 text-[13px] font-bold ${c.chip}`}>
      <span className={`size-2 rounded-full ${c.dot}`} />
      {GROUP_LABEL[group]}
    </span>
  )
}

/* ---------- result details ---------- */
export function TopThree({ d, animate = false }: { d: Detection; animate?: boolean }) {
  const [shown, setShown] = useState(!animate)
  useEffect(() => {
    if (!animate) return
    const id = requestAnimationFrame(() => requestAnimationFrame(() => setShown(true)))
    return () => cancelAnimationFrame(id)
  }, [animate])
  return (
    <ol className="space-y-2.5">
      {d.top_3.map((c, i) => {
        const sp = BY_ID[c.class_id]
        const name = c.common_name ?? sp?.common_name ?? c.class_id
        const pct = Math.round(c.probability * 100)
        const bar = sp ? GROUP_COLOR[sp.group].dot : 'bg-lichen'
        return (
          <li key={c.class_id}>
            <div className="mb-1 flex justify-between">
              <span className={i === 0 ? 'font-bold' : 'text-canopy-soft'}>{name}</span>
              <span className="tabular-nums text-canopy-soft">{pct}%</span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-mist">
              <div className={`fill-bar h-2 rounded-full ${bar} ${i === 0 ? '' : 'opacity-60'}`} style={{ width: shown ? `${Math.max(pct, 2)}%` : '0%' }} />
            </div>
          </li>
        )
      })}
    </ol>
  )
}

const Q_LABELS: [keyof Quality, string][] = [
  ['sharpness', 'Sharpness'],
  ['visibility', 'Animal visible'],
  ['exposure', 'Exposure'],
  ['resolution', 'Resolution'],
  ['composition', 'Composition'],
]

export function QualityBars({ q }: { q: Quality }) {
  return (
    <dl className="grid grid-cols-[auto_1fr_auto] items-center gap-x-3 gap-y-2 text-[14px]">
      {Q_LABELS.map(([k, label]) => (
        <div key={k} className="contents">
          <dt className="text-canopy-soft">{label}</dt>
          <dd className="h-1.5 rounded-full bg-mist">
            <div className="h-1.5 rounded-full bg-canopy-soft" style={{ width: `${q[k]}%` }} />
          </dd>
          <dd className="w-7 text-right tabular-nums">{q[k]}</dd>
        </div>
      ))}
    </dl>
  )
}

export function RatingBadge({ rating, size = 'md' }: { rating: number | null; size?: 'md' | 'lg' }) {
  if (rating === null) return null
  const big = size === 'lg'
  return (
    <span className="flex shrink-0 flex-col items-end leading-none" title="Photo rating: 65% photo quality, 35% identification confidence">
      <span className={`t-num ${big ? 'text-[40px]' : 'text-[28px]'}`}>{rating}</span>
      <span className="mt-1 text-[12px] text-canopy-soft">photo rating</span>
    </span>
  )
}

export function ModelNote({ post, className = '' }: { post: Pick<Post, 'sample' | 'prediction'>; className?: string }) {
  const p = post.prediction
  let text: string
  if (post.sample) text = 'Demo post. The species comes from iNaturalist; boxes and scores are sample values.'
  else if (p.model_version === 'demo') text = 'Demo result. The model API wasn’t running when this was posted, so the scores are placeholders.'
  else if (p.recorded_on) text = `Boxes and scores are real model output (${p.model_version}), recorded ${p.recorded_on}.`
  else text = `Identified by ${p.model_version}.`
  return <p className={`t-meta ${className}`}>{text}</p>
}

export function PageTitle({ children, sub }: { children: ReactNode; sub?: ReactNode }) {
  return (
    <div className="mb-6">
      <h1 className="t-display">{children}</h1>
      {sub && <p className="mt-2 max-w-[60ch] text-canopy-soft">{sub}</p>}
    </div>
  )
}

/* ---------- live model status from /healthz ---------- */
export interface Health {
  live: boolean
  model_version?: string
  detector_version?: string
}

let healthCache: Promise<Health> | null = null
export function useHealth(): Health | null {
  const [h, setH] = useState<Health | null>(null)
  useEffect(() => {
    healthCache ??= fetch('/healthz')
      .then((r) => (r.ok ? r.json() : Promise.reject()))
      .then((j) => ({ live: true, model_version: j.model_version, detector_version: j.detector_version }))
      .catch(() => ({ live: false }))
    let on = true
    healthCache.then((v) => on && setH(v))
    return () => {
      on = false
    }
  }, [])
  return h
}

export function timeAgo(date: string) {
  if (!date) return ''
  const d = new Date(date)
  const days = Math.floor((Date.now() - d.getTime()) / 86400000)
  if (days < 1) return 'today'
  if (days < 2) return 'yesterday'
  if (days < 30) return `${days} days ago`
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
}
