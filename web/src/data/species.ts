import raw from './species.json'
import type { Group, Species } from '../types'

export const SPECIES = raw as Species[]
export const BY_ID: Record<string, Species> = Object.fromEntries(SPECIES.map((s) => [s.class_id, s]))

export const GROUP_LABEL: Record<Group, string> = {
  large_mammal: 'Large mammals',
  small_mammal: 'Small mammals',
  bird: 'Birds',
}

/** Label shown when the gate falls back to a group (M10 rollup). */
export const GROUP_ROLLUP: Record<Group, string> = {
  large_mammal: 'Large mammal (species uncertain)',
  small_mammal: 'Small mammal (species uncertain)',
  bird: 'Bird (species uncertain)',
}
