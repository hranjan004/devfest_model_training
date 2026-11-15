import { useMemo } from 'react'
import { GROUP_COLOR, Icon, PageTitle } from '../components'
import { BY_ID, GROUP_LABEL, SPECIES } from '../data/species'
import { href } from '../router'
import { primaryOf, useStore } from '../store'
import type { Group, Post } from '../types'
import { PostCard } from './Feed'

function useByClass() {
  const { posts } = useStore()
  return useMemo(() => {
    const m: Record<string, Post[]> = {}
    for (const p of posts) {
      const id = primaryOf(p)?.species?.class_id
      if (id) (m[id] ??= []).push(p)
    }
    return m
  }, [posts])
}

/** Posts whose best guess is this species (used only for a cover photo when none is identified). */
function useGuesses() {
  const { posts } = useStore()
  return useMemo(() => {
    const m: Record<string, Post[]> = {}
    for (const p of posts) {
      const id = primaryOf(p)?.top_3[0]?.class_id
      if (id) (m[id] ??= []).push(p)
    }
    return m
  }, [posts])
}

export function SpeciesIndex() {
  const byClass = useByClass()
  const guesses = useGuesses()
  const groups: Group[] = ['large_mammal', 'small_mammal', 'bird']
  return (
    <div>
      <PageTitle sub="The 20 animals the model knows, all recorded on the UCSC Campus Natural Reserve.">Species guide</PageTitle>
      {groups.map((g) => (
        <section key={g} className="mb-10" aria-labelledby={`g-${g}`}>
          <h2 id={`g-${g}`} className="mb-4 flex items-center gap-2.5 t-heading"><span className={`size-2.5 rounded-full ${GROUP_COLOR[g].dot}`} />{GROUP_LABEL[g]}</h2>
          <ul className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
            {SPECIES.filter((s) => s.group === g).map((s) => {
              const posts = byClass[s.class_id] ?? []
              const cover = posts[0] ?? guesses[s.class_id]?.[0]
              return (
                <li key={s.class_id}>
                  <a href={href.speciesDetail(s.class_id)} className="group block">
                    <div className="aspect-[4/5] overflow-hidden rounded-xl bg-mist">
                      {cover && <img src={cover.image} alt="" loading="lazy" className="size-full object-cover transition-transform duration-300 group-hover:scale-[1.03]" />}
                    </div>
                    <p className="mt-2 font-bold leading-tight">{s.common_name}</p>
                    <p className="t-meta">
                      {posts.length} identified {posts.length === 1 ? 'sighting' : 'sightings'}
                    </p>
                  </a>
                </li>
              )
            })}
          </ul>
        </section>
      ))}
    </div>
  )
}

export function SpeciesDetail({ classId }: { classId: string }) {
  const byClass = useByClass()
  const sp = BY_ID[classId]
  if (!sp) return <p className="py-20 text-center">That species isn’t one of the 20.</p>
  const posts = byClass[classId] ?? []
  return (
    <div>
      <a href={href.species} className="mb-4 inline-flex min-h-11 items-center gap-1 text-canopy-soft hover:text-canopy">
        {Icon.back('size-5')} All species
      </a>
      <PageTitle sub={<><i>{sp.scientific_name}</i>{sp.campus_habitat && <>. On campus: {sp.campus_habitat.toLowerCase()}.</>}</>}>{sp.common_name}</PageTitle>
      {posts.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-lichen p-10 text-center">
          <p className="t-heading">No identified sightings yet.</p>
          <a href={href.identify} className="mt-3 inline-block rounded-full bg-redwood px-5 py-2.5 font-bold text-white">Identify an animal</a>
        </div>
      ) : (
        <ul className="grid gap-8 md:grid-cols-2">
          {posts.map((p) => (
            <li key={p.id}>
              <PostCard post={p} />
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
