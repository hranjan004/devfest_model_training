import { useMemo, useState } from 'react'
import { labelOf, PageTitle, RatingBadge } from '../components'
import { GROUP_LABEL } from '../data/species'
import { href } from '../router'
import { primaryOf, useStore } from '../store'
import type { Group } from '../types'

type Filter = 'all' | Group

export function Rankings() {
  const { posts } = useStore()
  const [filter, setFilter] = useState<Filter>('all')
  const ranked = useMemo(
    () =>
      posts
        .map((p) => ({ p, d: primaryOf(p) }))
        .filter(({ d }) => d?.rating != null && (filter === 'all' || d.species?.group === filter))
        .sort((a, b) => b.d!.rating! - a.d!.rating!)
        .slice(0, 25),
    [posts, filter],
  )
  const filters: Filter[] = ['all', 'large_mammal', 'small_mammal', 'bird']

  return (
    <div className="mx-auto max-w-3xl">
      <PageTitle sub="Ranked by photo rating: 65% photo quality and 35% how confidently the model identified the animal. Uncertain IDs aren’t ranked.">Best photos</PageTitle>
      <div className="mb-6 flex flex-wrap gap-2" role="radiogroup" aria-label="Filter by group">
        {filters.map((f) => (
          <button key={f} role="radio" aria-checked={filter === f} onClick={() => setFilter(f)} className="min-h-9 rounded-full border border-line px-3.5 text-[14px] text-canopy-soft transition-colors hover:border-canopy-soft aria-checked:border-canopy aria-checked:bg-canopy aria-checked:font-bold aria-checked:text-fog">
            {f === 'all' ? 'Everything' : GROUP_LABEL[f]}
          </button>
        ))}
      </div>
      <ol className="space-y-3">
        {ranked.map(({ p, d }, i) => (
          <li key={p.id}>
            <a href={href.post(p.id)} className="flex items-center gap-3 rounded-[18px] bg-paper p-3 pr-4 sm:gap-4 sm:pr-5 shadow-[0_1px_0_var(--color-line)] hover:ring-2 hover:ring-lichen">
              <span className={`t-num w-8 shrink-0 text-center sm:w-10 ${i < 3 ? 'text-[34px] text-redwood' : 'text-[24px] text-canopy-soft'}`}>{i + 1}</span>
              <img src={p.image} alt="" loading="lazy" className={`shrink-0 rounded-xl object-cover ${i === 0 ? 'size-16 sm:size-28' : 'size-16 sm:size-20'}`} />
              <div className="min-w-0 flex-1">
                <p className="truncate t-heading">{labelOf(d!)}</p>
                <p className="t-meta truncate">{p.author}, {p.place}</p>
              </div>
              <RatingBadge rating={d!.rating} />
            </a>
          </li>
        ))}
      </ol>
      {posts.some((p) => p.sample) && <p className="t-meta mt-6">Ratings on demo posts are sample values.</p>}
    </div>
  )
}
