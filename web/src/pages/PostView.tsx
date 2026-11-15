import { useState, type FormEvent } from 'react'
import { Circle, MapContainer, TileLayer } from 'react-leaflet'
import 'leaflet/dist/leaflet.css'
import { DetectionPhoto, GroupChip, groupOf, Icon, labelOf, ModelNote, QualityBars, RatingBadge, timeAgo, TopThree } from '../components'
import { BY_ID } from '../data/species'
import { href } from '../router'
import { useStore } from '../store'

export function PostView({ id }: { id: string }) {
  const { posts, dispatch } = useStore()
  const post = posts.find((p) => p.id === id)
  const [sel, setSel] = useState(post?.prediction.primary_index ?? 0)
  const [text, setText] = useState('')

  if (!post) {
    return (
      <div className="py-24 text-center">
        <p className="t-title">This post isn’t here anymore.</p>
        <a href={href.feed} className="mt-4 inline-block text-redwood underline">Back to the feed</a>
      </div>
    )
  }
  const d = post.prediction.detections[sel]
  const sp = d?.species ? BY_ID[d.species.class_id] : undefined
  const multi = post.prediction.detections.length > 1

  const submit = (e: FormEvent) => {
    e.preventDefault()
    const t = text.trim()
    if (!t) return
    dispatch({ type: 'comment', id: post.id, comment: { id: crypto.randomUUID(), author: 'You', text: t.slice(0, 500), at: new Date().toISOString() } })
    setText('')
  }

  return (
    <div>
      <a href={href.feed} className="mb-4 inline-flex min-h-11 items-center gap-1 text-canopy-soft hover:text-canopy">
        {Icon.back('size-5')} Sightings
      </a>
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)] lg:gap-10">
        <div className="space-y-3">
          <DetectionPhoto post={post} className="rounded-2xl" selected={multi ? sel : undefined} onSelect={multi ? setSel : undefined} />
          {multi && <p className="text-[14px] text-canopy-soft">{post.prediction.detections.length} animals found. Tap a box to see its result.</p>}
          {post.attribution && (
            <p className="t-meta">
              Photo {post.attribution.startsWith('no rights') ? `by ${post.author}, no rights reserved (CC0)` : post.attribution}.{' '}
              <a href={post.source} target="_blank" rel="noreferrer" className="underline">
                iNaturalist observation
              </a>
            </p>
          )}
        </div>

        <div className="space-y-7">
          <div>
            <div className="flex items-start justify-between gap-4">
              <div>
                <h1 className="t-display">{d ? labelOf(d) : 'No animal found'}</h1>
                {sp && (
                  <p className="mt-1 text-canopy-soft">
                    <i>{sp.scientific_name}</i>
                  </p>
                )}
              </div>
              <RatingBadge rating={d?.rating ?? null} size="lg" />
            </div>
            <p className="mt-3 text-canopy-soft">
              Seen by {post.author} near {post.place}, {timeAgo(post.observed_on)}.
            </p>
            {sp?.campus_habitat && <p className="mt-1 text-canopy-soft">On campus: {sp.campus_habitat.toLowerCase()}.</p>}
            <div className="mt-3 flex flex-wrap items-center gap-3">
              <GroupChip group={groupOf(d)} />
              <ModelNote post={post} />
            </div>
          </div>

          {d && d.top_3.length > 0 && (
            <section aria-labelledby="h-top3">
              <h2 id="h-top3" className="mb-3 t-heading">How sure the model is</h2>
              <TopThree d={d} />
            </section>
          )}

          {d && (
            <section aria-labelledby="h-q">
              <h2 id="h-q" className="mb-3 t-heading">Photo quality {d.quality.overall}</h2>
              <QualityBars q={d.quality} />
            </section>
          )}

          <section aria-labelledby="h-map">
            <h2 id="h-map" className="mb-3 t-heading">Where</h2>
            <div className="h-56 overflow-hidden rounded-2xl ring-1 ring-line">
              <MapContainer center={[post.lat, post.lng]} zoom={13} scrollWheelZoom={false} className="size-full">
                <TileLayer attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
                <Circle center={[post.lat, post.lng]} radius={600} pathOptions={{ color: '#6b2e1f', fillColor: '#f2c230', fillOpacity: 0.35, weight: 2 }} />
              </MapContainer>
            </div>
            <p className="t-meta mt-2">Shown within about a kilometre to protect the animal and the photographer.</p>
          </section>

          <section aria-labelledby="h-c">
            <h2 id="h-c" className="mb-3 t-heading">Comments</h2>
            {post.comments.length === 0 && <p className="text-canopy-soft">No comments yet. Say what you noticed.</p>}
            <ul className="space-y-3">
              {post.comments.map((c) => (
                <li key={c.id} className="text-[15px]">
                  <b>{c.author}</b> {c.text}
                </li>
              ))}
            </ul>
            <form onSubmit={submit} className="mt-4 flex gap-2">
              <label htmlFor="comment" className="sr-only">Add a comment</label>
              <input id="comment" value={text} onChange={(e) => setText(e.target.value)} placeholder="Add a comment" className="min-w-0 flex-1 rounded-full border border-line bg-white px-4 py-2.5" />
              <button disabled={!text.trim()} className="rounded-full bg-canopy px-5 font-bold text-fog disabled:opacity-40">Post</button>
            </form>
          </section>
        </div>
      </div>
    </div>
  )
}
