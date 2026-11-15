import type { PredictionV2 } from './types'
import { demoPredict } from './mock'

export type Source = 'api' | 'demo'

/**
 * POST the photo to /v2/predict on the FastAPI service. If the service isn't
 * running, fall back to the in-browser demo predictor and say so in the UI.
 */
export async function predict(file: File, dims: { width: number; height: number }): Promise<{ result: PredictionV2; source: Source }> {
  const body = new FormData()
  body.append('file', file)
  try {
    const res = await fetch('/v2/predict', { method: 'POST', body })
    if (res.ok) return { result: (await res.json()) as PredictionV2, source: 'api' }
    if (res.status >= 400 && res.status < 500) {
      const err = await res.json().catch(() => ({}))
      throw new PredictError(err.detail ?? `The service rejected this photo (${res.status}).`)
    }
  } catch (e) {
    if (e instanceof PredictError) throw e
  }
  return { result: await demoPredict(file, dims), source: 'demo' }
}

export class PredictError extends Error {}

/** Corrections go to the human review queue only; they never retrain the model directly. */
export async function sendFeedback(payload: {
  predicted_class_id: string | null
  corrected_class_id: string
  notes?: string
}): Promise<boolean> {
  try {
    const res = await fetch('/v1/feedback', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, consent: true }),
    })
    return res.status === 202
  } catch {
    return false
  }
}
