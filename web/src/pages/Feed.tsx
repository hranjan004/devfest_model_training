import { useMemo, useState } from 'react'
import { DetectionPhoto, GroupChip, groupOf, Icon, labelOf, RatingBadge, timeAgo } from '../components'
import { FieldStation } from './FieldStation'
import { BY_ID } from '../data/species'
import { href } from '../router'
import { primaryOf, useStore } from '../store'
import type { Post } from '../types'

const SORTS = [
  { key: 'new', label: 'Newest' },
  { key: 'rated', label: 'Best photos' },
  { key: 'liked', label: 'Most liked' },
] as const
type SortKey = (typeof SORTS)[number]['key']

export function sortPosts(posts: Post[], key: SortKey) {
  const copy = [...posts]
  if (key === 'rated') return copy.sort((a, b) => (primaryOf(b)?.rating ?? -1) - (primaryOf(a)?.rating ?? -1))
  if (key === 'liked') return copy.sort((a, b) => b.likes - a.likes)
  return copy.sort((a, b) => (Number(!a.sample) - Number(!b.sample)) * -1 || b.observed_on.localeCompare(a.observed_on))
}

export function Feed() {
  const { posts } = useStore()
  const [sort, setSort] = useState<SortKey>('new')
  const sorted = useMemo(() => sortPosts(posts, sort), [posts, sort])

  return (
    <div className="flex justify-center gap-8">
      <div className="w-full max-w-[560px] min-w-0">
        <div className="sticky top-0 z-10 -mx-4 mb-5 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-3 bg-fog/95 px-4 py-3 backdrop-blur">
          <h1 className="t-display">Seen on campus</h1>
          <div className="flex gap-1.5" role="radiogroup" aria-label="Sort posts">
            {SORTS.map((s) => (
              <button
                key={s.key}
                role="radio"
                aria-checked={sort === s.key}
                onClick={() => setSort(s.key)}
                className="min-h-9 rounded-full border border-line px-3.5 text-[14px] text-canopy-soft transition-colors hover:border-canopy-soft aria-checked:border-canopy aria-checked:bg-canopy aria-checked:font-bold aria-checked:text-fog"
              >
                {s.label}
              </button>
            ))}
          </div>
        </div>
        <ul className="space-y-6">
          {sorted.map((p) => (
            <li key={p.id}>
              <PostCard post={p} />
            </li>
          ))}
        </ul>
      </div>
      <FieldStation />
    </div>
  )
}

export function PostCard({ post }: { post: Post }) {
  const { dispatch } = useStore()
  const d = primaryOf(post)
  const sp = d?.species ? BY_ID[d.species.class_id] : undefined
  return (
    <article className="overflow-hidden rounded-[18px] bg-paper shadow-[0_1px_0_var(--color-line)]">
      <header className="flex items-center gap-3 px-4 py-3.5">
        <span className="grid size-9 place-items-center rounded-full bg-canopy font-display font-bold text-fog">{post.author.slice(0, 1).toUpperCase()}</span>
        <div className="min-w-0 leading-tight">
          <p className="truncate font-bold">{post.author}</p>
          <p className="t-meta truncate">
            {post.place}, {timeAgo(post.observed_on)}
          </p>
        </div>
      </header>
      <a href={href.post(post.id)} className="block">
        <DetectionPhoto post={post} />
      </a>
      <div className="px-4 pt-3.5 pb-4">
        <div className="flex items-start justify-between gap-3">
          <a href={href.post(post.id)} className="min-w-0">
            <h2 className="t-title">{d ? labelOf(d) : 'No animal found'}</h2>
            {sp && <p className="mt-0.5 text-[14px] text-canopy-soft italic">{sp.scientific_name}</p>}
          </a>
          <RatingBadge rating={d?.rating ?? null} />
        </div>
        <div className="mt-3 flex items-center gap-5 text-canopy-soft">
          <GroupChip group={groupOf(d)} />
          <button onClick={() => dispatch({ type: 'like', id: post.id })} aria-pressed={post.liked} className="flex items-center gap-1.5 hover:text-redwood aria-pressed:text-redwood">
            {Icon.heart('size-6', post.liked)}
            <span className="tabular-nums">{post.likes}</span>
            <span className="sr-only">likes</span>
          </button>
          <a href={href.post(post.id)} className="flex items-center gap-1.5 hover:text-canopy">
            {Icon.comment()}
            <span className="tabular-nums">{post.comments.length}</span>
            <span className="sr-only">comments</span>
          </a>
        </div>
      </div>
    </article>
  )
}
