import { useMemo } from 'react'
import { GROUP_COLOR, groupOf, labelOf, useHealth } from '../components'
import { GROUP_LABEL } from '../data/species'
import { href } from '../router'
import { primaryOf, useStore } from '../store'
import type { Group } from '../types'

const GROUPS: Group[] = ['bird', 'large_mammal', 'small_mammal']

/** Desktop right rail: live model status, what the feed holds, and the best photos. */
export function FieldStation() {
  const { posts } = useStore()
  const health = useHealth()
  const counts = useMemo(() => {
    const c: Record<Group, number> = { bird: 0, large_mammal: 0, small_mammal: 0 }
    for (const p of posts) {
      const g = groupOf(primaryOf(p))
      if (g) c[g]++
    }
    return c
  }, [posts])
  const max = Math.max(1, ...Object.values(counts))
  const top = useMemo(
    () =>
      posts
        .map((p) => ({ p, d: primaryOf(p) }))
        .filter(({ d }) => d?.rating != null)
        .sort((a, b) => b.d!.rating! - a.d!.rating!)
        .slice(0, 3),
    [posts],
  )

  return (
    <aside aria-label="Field station" className="sticky top-7 hidden w-[300px] shrink-0 space-y-5 self-start xl:block">
      <section className="space-y-3.5 rounded-[18px] bg-canopy p-[18px] text-fog">
        <div className="flex items-center justify-between">
          <h2 className="t-heading">Model status</h2>
          <span className="flex items-center gap-1.5 text-[13px] text-[#c8d6c4]" aria-live="polite">
            <span className={`size-2 rounded-full ${health === null ? 'bg-lichen' : health.live ? 'bg-live' : 'bg-slug'}`} />
            {health === null ? 'Checking' : health.live ? 'Live' : 'Demo mode'}
          </span>
        </div>
        <dl className="grid grid-cols-[auto_1fr] gap-x-3.5 gap-y-1.5 text-[14px]">
          <dt className="text-[#b8c9b4]">Finds animals</dt>
          <dd className="text-right">MegaDetector V6</dd>
          <dt className="text-[#b8c9b4]">Names species</dt>
          <dd className="text-right">BioCLIP 2, 20 species</dd>
          <dt className="text-[#b8c9b4]">Version</dt>
          <dd className="truncate text-right" title={health?.model_version}>{health?.live ? health.model_version : 'not connected'}</dd>
        </dl>
        {health && !health.live && <p className="text-[13px] text-[#c8d6c4]">Start the FastAPI service to identify new photos with the real model.</p>}
      </section>

      <section className="space-y-3 rounded-[18px] bg-paper p-[18px] shadow-[0_1px_0_var(--color-line)]">
        <h2 className="t-heading">On the feed</h2>
        <ul className="space-y-2.5 text-[14px]">
          {GROUPS.map((g) => (
            <li key={g} className="grid grid-cols-[110px_1fr_28px] items-center gap-2.5">
              <span>{GROUP_LABEL[g]}</span>
              <span className="h-2.5 overflow-hidden rounded-full bg-mist">
                <span className={`block h-full rounded-full ${GROUP_COLOR[g].dot}`} style={{ width: `${(counts[g] / max) * 100}%` }} />
              </span>
              <span className="text-right tabular-nums">{counts[g]}</span>
            </li>
          ))}
        </ul>
        <p className="t-meta">Grouped by the model’s best guess for each post.</p>
      </section>

      {top.length > 0 && (
        <section className="space-y-3 rounded-[18px] bg-paper p-[18px] shadow-[0_1px_0_var(--color-line)]">
          <h2 className="t-heading">Top rated</h2>
          <ol className="space-y-2.5">
            {top.map(({ p, d }) => (
              <li key={p.id}>
                <a href={href.post(p.id)} className="grid grid-cols-[52px_1fr_auto] items-center gap-3 rounded-xl hover:bg-mist">
                  <img src={p.image} alt="" className="size-[52px] rounded-[10px] object-cover" loading="lazy" />
                  <span className="truncate font-bold">{labelOf(d!)}</span>
                  <span className="t-num pr-1 text-[20px]">{d!.rating}</span>
                </a>
              </li>
            ))}
          </ol>
          <a href={href.rankings} className="inline-block text-[14px] font-bold text-redwood underline-offset-2 hover:underline">See all rankings</a>
        </section>
      )}
    </aside>
  )
}
