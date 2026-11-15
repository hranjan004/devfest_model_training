import { useEffect, useRef, useState, type ChangeEvent } from 'react'
import { predict, PredictError, sendFeedback, type Source } from '../api'
import { DetectionPhoto, GROUP_COLOR, GroupChip, groupOf, Icon, labelOf, PageTitle, QualityBars, RatingBadge, TopThree } from '../components'
import { BY_ID, GROUP_LABEL, SPECIES } from '../data/species'
import { href } from '../router'
import { useStore } from '../store'
import type { Detection, Group, PredictionV2 } from '../types'

const SPOTS = [
  { name: 'East Field', lat: 36.99, lng: -122.05 },
  { name: 'Arboretum', lat: 36.98, lng: -122.06 },
  { name: 'Great Meadow', lat: 36.98, lng: -122.06 },
  { name: 'Porter Meadow', lat: 36.99, lng: -122.07 },
  { name: 'Upper Campus', lat: 37.01, lng: -122.07 },
  { name: 'Campus Natural Reserve', lat: 37.0, lng: -122.06 },
]

interface Shot {
  file: File
  url: string // downscaled JPEG data URL, also what gets posted
  width: number
  height: number
}

type Phase = { k: 'pick' } | { k: 'working'; shot: Shot } | { k: 'done'; shot: Shot; result: PredictionV2; source: Source } | { k: 'error'; shot: Shot; message: string }

async function prepare(file: File): Promise<Shot> {
  const bmp = await createImageBitmap(file)
  const scale = Math.min(1, 1280 / Math.max(bmp.width, bmp.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bmp.width * scale)
  canvas.height = Math.round(bmp.height * scale)
  canvas.getContext('2d')!.drawImage(bmp, 0, 0, canvas.width, canvas.height)
  // Re-encoding through a canvas also drops EXIF (including GPS).
  return { file, url: canvas.toDataURL('image/jpeg', 0.82), width: bmp.width, height: bmp.height }
}

export function Identify() {
  const [phase, setPhase] = useState<Phase>({ k: 'pick' })
  const input = useRef<HTMLInputElement>(null)

  const onFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    if (!file.type.startsWith('image/')) return
    const shot = await prepare(file)
    setPhase({ k: 'working', shot })
    try {
      const { result, source } = await predict(file, { width: shot.width, height: shot.height })
      setPhase({ k: 'done', shot, result, source })
    } catch (err) {
      setPhase({ k: 'error', shot, message: err instanceof PredictError ? err.message : 'Something went wrong reading this photo. Try another one.' })
    }
  }

  return (
    <div className="mx-auto max-w-5xl">
      <input ref={input} type="file" accept="image/*" capture="environment" onChange={onFile} className="sr-only" id="photo" />
      {phase.k === 'pick' && (
        <>
          <PageTitle sub="Take or choose a photo. The detector finds each animal, then the classifier names it from the 20 campus species.">Identify an animal</PageTitle>
          <label htmlFor="photo" className="group grid aspect-[4/3] max-h-[60vh] w-full cursor-pointer place-items-center rounded-3xl border-2 border-dashed border-lichen bg-paper text-center transition-colors hover:border-canopy">
            <span>
              <span className="bracket mx-auto mb-5 block size-24 [--c:var(--color-canopy)] [--l:32%] group-hover:[--c:var(--color-redwood)]" />
              <span className="block t-title">Choose a photo</span>
              <span className="mt-1 block text-canopy-soft">or take one with your camera</span>
            </span>
          </label>
          <p className="t-meta mt-4">Location data is removed from your photo before anything is sent.</p>
        </>
      )}

      {phase.k === 'working' && (
        <div className="grid gap-8 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)]">
          <div className="scan relative overflow-hidden rounded-2xl bg-canopy">
            <img src={phase.shot.url} alt="Your photo" className="w-full opacity-80" />
            <span className="bracket absolute inset-[2%]" data-status="uncertain" />
          </div>
          <div aria-live="polite">
            <p className="t-title">Looking for animals</p>
            <p className="mt-2 text-canopy-soft">MegaDetector finds each animal, then BioCLIP 2 names it.</p>
          </div>
        </div>
      )}

      {phase.k === 'error' && (
        <div className="mx-auto max-w-md py-16 text-center">
          <p className="t-title">That photo didn’t work.</p>
          <p className="mt-2 text-canopy-soft">{phase.message}</p>
          <label htmlFor="photo" className="mt-6 inline-flex min-h-12 cursor-pointer items-center rounded-xl bg-redwood px-6 font-bold text-white">Choose another photo</label>
        </div>
      )}

      {phase.k === 'done' && <Result shot={phase.shot} result={phase.result} source={phase.source} />}
    </div>
  )
}

function Result({ shot, result, source }: { shot: Shot; result: PredictionV2; source: Source }) {
  const { dispatch } = useStore()
  const [sel, setSel] = useState(result.primary_index ?? 0)
  const [dets, setDets] = useState(result.detections)
  const [correcting, setCorrecting] = useState<string | false>(false)
  const [spot, setSpot] = useState(SPOTS[0].name)
  const d: Detection | undefined = dets[sel]
  const pred = { ...result, detections: dets, primary: dets[result.primary_index ?? 0] ?? null }

  const post = () => {
    const s = SPOTS.find((x) => x.name === spot)!
    const id = `mine-${crypto.randomUUID()}`
    dispatch({
      type: 'add',
      post: { id, image: shot.url, width: shot.width, height: shot.height, author: 'You', observed_on: new Date().toISOString().slice(0, 10), place: s.name, lat: s.lat, lng: s.lng, prediction: pred, likes: 0, liked: false, comments: [], sample: false },
    })
    location.hash = href.post(id)
  }

  if (!dets.length || result.status === 'no_animal') {
    return (
      <div className="grid gap-8 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)]">
        <img src={shot.url} alt="Your photo" className="w-full rounded-2xl" />
        <div>
          <h1 className="t-display">No animal found</h1>
          <p className="mt-3 max-w-[48ch] text-canopy-soft">The detector couldn’t find a wild animal here. People, pets and cars are skipped on purpose. If there is an animal, try a closer photo where it fills more of the frame.</p>
          <label htmlFor="photo" className="mt-6 inline-flex min-h-12 cursor-pointer items-center rounded-xl bg-redwood px-6 font-bold text-white">Try another photo</label>
        </div>
      </div>
    )
  }

  return (
    <div className="grid gap-8 lg:grid-cols-[minmax(0,1.25fr)_minmax(0,1fr)] lg:gap-10">
      <div className="space-y-3">
        <DetectionPhoto post={{ image: shot.url, width: shot.width, height: shot.height, prediction: pred }} animate className="rounded-2xl" selected={dets.length > 1 ? sel : undefined} onSelect={dets.length > 1 ? setSel : undefined} />
        {dets.length > 1 && <p className="text-[14px] text-canopy-soft">{dets.length} animals found. Tap a box to see each one.</p>}
        {source === 'demo' && (
          <p className="rounded-xl bg-slug/30 px-4 py-3 text-[14px]">
            <b>Demo result.</b> The model API isn’t running, so this species was picked at random to show the flow. Start the FastAPI service to get real predictions.
          </p>
        )}
      </div>

      {d && (
        <div className="space-y-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h1 className="t-display">{labelOf(d)}</h1>
              {d.species && d.status === 'identified' && <p className="mt-1 text-canopy-soft italic">{d.species.scientific_name}</p>}
            </div>
            <RatingBadge rating={d.rating} size="lg" />
          </div>
          <div className="flex flex-wrap gap-2 text-[13px]">
            <span className="inline-flex h-7 items-center gap-1.5 rounded-full bg-mist px-2.5">{Icon.check('size-3.5')}Found {dets.length} {dets.length === 1 ? 'animal' : 'animals'}</span>
            <span className={`inline-flex h-7 items-center gap-1.5 rounded-full px-2.5 ${d.status === 'identified' ? 'bg-slug font-bold' : 'border border-dashed border-canopy-soft bg-paper'}`}>
              {d.status === 'identified' ? `Named with ${Math.round((d.confidence_calibrated ?? 0) * 100)}% confidence` : d.status === 'uncertain' ? 'Species check: low confidence' : 'Not a campus species'}
            </span>
            <GroupChip group={groupOf(d)} />
          </div>

          {d.status === 'uncertain' && (
            <p>The model’s best guess is under its 78% bar, so it won’t name it outright. Pick the right one below to help it learn, or post it as is.</p>
          )}
          {d.status === 'unsupported' && <p>This looks like an animal, but not one of the 20 campus species the model knows.</p>}

          {d.top_3.length > 0 && d.status === 'uncertain' && (
            <section>
              <h2 className="mb-3 t-heading">Which one is it?</h2>
              <ul className="space-y-2">
                {d.top_3.map((c, i) => {
                  const sp = BY_ID[c.class_id]
                  const pct = Math.round(c.probability * 100)
                  return (
                    <li key={c.class_id}>
                      <button
                        onClick={() => setCorrecting(c.class_id)}
                        className={`grid min-h-11 w-full grid-cols-[1fr_96px_40px] items-center gap-3 rounded-xl bg-white px-3 text-left transition-colors hover:border-canopy ${i === 0 ? 'border-2 border-canopy font-bold' : 'border border-line'}`}
                      >
                        {sp?.common_name ?? c.class_id}
                        <span className="h-2 overflow-hidden rounded-full bg-mist">
                          <span className={`fill-bar block h-full rounded-full ${sp ? GROUP_COLOR[sp.group].dot : 'bg-lichen'}`} style={{ width: `${Math.max(pct, 2)}%` }} />
                        </span>
                        <span className="text-right tabular-nums">{pct}%</span>
                      </button>
                    </li>
                  )
                })}
              </ul>
            </section>
          )}
          {d.top_3.length > 0 && d.status !== 'uncertain' && (
            <section>
              <h2 className="mb-3 t-heading">Top matches</h2>
              <TopThree d={d} animate />
            </section>
          )}
          <section>
            <h2 className="mb-3 t-heading">Photo quality {d.quality.overall}</h2>
            <QualityBars q={d.quality} />
          </section>

          <div className="space-y-3 border-t border-line pt-5">
            <label className="block text-[15px]">
              <span className="mb-1 block font-bold">Where on campus?</span>
              <select value={spot} onChange={(e) => setSpot(e.target.value)} className="w-full rounded-xl border border-line bg-white px-3 py-2.5">
                {SPOTS.map((s) => (
                  <option key={s.name}>{s.name}</option>
                ))}
              </select>
            </label>
            <div className="flex flex-wrap gap-3">
              <button onClick={post} className="min-h-12 rounded-xl bg-redwood px-6 font-bold text-white transition-colors hover:bg-redwood-dark">Post sighting</button>
              <button onClick={() => setCorrecting('')} className="min-h-12 rounded-xl border border-canopy px-6 font-bold">{d.status === 'identified' ? 'That’s not right' : 'None of these'}</button>
            </div>
          </div>
        </div>
      )}

      {correcting !== false && d && (
        <CorrectDialog
          initial={correcting}
          current={d.species?.class_id ?? null}
          onClose={() => setCorrecting(false)}
          onPick={(classId) => {
            const sp = BY_ID[classId]
            setDets(dets.map((x, i) => (i === sel ? { ...x, status: 'identified', species: { class_id: sp.class_id, common_name: sp.common_name, scientific_name: sp.scientific_name, group: sp.group }, box_source: x.box_source, coarse_group_fallback: undefined, rating: null } : x)))
            setCorrecting(false)
          }}
        />
      )}
    </div>
  )
}

function CorrectDialog({ initial, current, onClose, onPick }: { initial: string; current: string | null; onClose: () => void; onPick: (classId: string) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const [choice, setChoice] = useState<string>(initial)
  const [share, setShare] = useState(true)
  const [sent, setSent] = useState<null | boolean>(null)
  useEffect(() => {
    ref.current?.showModal()
  }, [])

  const save = async () => {
    if (!choice) return
    if (share) setSent(await sendFeedback({ predicted_class_id: current, corrected_class_id: choice }))
    if (choice !== 'unknown') onPick(choice)
    else onClose()
  }

  return (
    <dialog ref={ref} onClose={onClose} className="m-auto w-[min(92vw,460px)] rounded-3xl bg-fog p-0 text-canopy backdrop:bg-canopy/60">
      <div className="p-6">
        <h2 className="t-title">What is it?</h2>
        <p className="mt-1 text-canopy-soft">Your answer replaces the model’s label on this post.</p>
        <label className="mt-4 block">
          <span className="sr-only">Species</span>
          <select value={choice} onChange={(e) => setChoice(e.target.value)} className="w-full rounded-xl border border-line bg-white px-3 py-3">
            <option value="">Choose a species</option>
            {(['large_mammal', 'small_mammal', 'bird'] as Group[]).map((g) => (
              <optgroup key={g} label={GROUP_LABEL[g]}>
                {SPECIES.filter((s) => s.group === g).map((s) => (
                  <option key={s.class_id} value={s.class_id} disabled={s.class_id === current}>
                    {s.common_name}
                  </option>
                ))}
              </optgroup>
            ))}
            <option value="unknown">Something else, not on this list</option>
          </select>
        </label>
        <label className="mt-4 flex items-start gap-3 text-[14px]">
          <input type="checkbox" checked={share} onChange={(e) => setShare(e.target.checked)} className="mt-1 size-4 accent-canopy" />
          <span>Send this correction to the project team for review. It helps them find mistakes; it doesn’t change the model on its own.</span>
        </label>
        {sent === false && <p className="mt-3 text-[14px] text-redwood">The review service isn’t reachable, so the correction was only saved on this post.</p>}
        <div className="mt-6 flex justify-end gap-3">
          <button onClick={onClose} className="min-h-11 rounded-xl px-5 font-bold text-canopy-soft">Cancel</button>
          <button onClick={save} disabled={!choice} className="min-h-11 rounded-xl bg-canopy px-5 font-bold text-fog disabled:opacity-40">Save correction</button>
        </div>
      </div>
    </dialog>
  )
}
