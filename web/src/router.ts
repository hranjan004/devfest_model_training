import { useEffect, useState } from 'react'

export type Route =
  | { name: 'feed' }
  | { name: 'post'; id: string }
  | { name: 'species' }
  | { name: 'speciesDetail'; classId: string }
  | { name: 'rankings' }
  | { name: 'identify' }

export function parse(hash: string): Route {
  const parts = hash.replace(/^#\/?/, '').split('/').filter(Boolean)
  switch (parts[0]) {
    case 'post':
      return parts[1] ? { name: 'post', id: decodeURIComponent(parts[1]) } : { name: 'feed' }
    case 'species':
      return parts[1] ? { name: 'speciesDetail', classId: parts[1] } : { name: 'species' }
    case 'rankings':
      return { name: 'rankings' }
    case 'identify':
      return { name: 'identify' }
    default:
      return { name: 'feed' }
  }
}

export const href = {
  feed: '#/',
  post: (id: string) => `#/post/${encodeURIComponent(id)}`,
  species: '#/species',
  speciesDetail: (id: string) => `#/species/${id}`,
  rankings: '#/rankings',
  identify: '#/identify',
}

export function useRoute(): Route {
  const [route, setRoute] = useState(() => parse(location.hash))
  useEffect(() => {
    const on = () => {
      setRoute(parse(location.hash))
      window.scrollTo(0, 0)
    }
    addEventListener('hashchange', on)
    return () => removeEventListener('hashchange', on)
  }, [])
  return route
}
