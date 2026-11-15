import { SideNav, TabBar } from './components'
import { useRoute } from './router'
import { StoreProvider } from './store'
import { Feed } from './pages/Feed'
import { Identify } from './pages/Identify'
import { PostView } from './pages/PostView'
import { Rankings } from './pages/Rankings'
import { SpeciesDetail, SpeciesIndex } from './pages/Species'

export default function App() {
  const route = useRoute()
  return (
    <StoreProvider>
      <div className="mx-auto flex max-w-[1440px]">
        <SideNav route={route} />
        <main key={route.name} className="min-w-0 flex-1 px-4 pt-5 pb-28 md:px-8 md:pt-7 md:pb-16">
          {route.name === 'feed' && <Feed />}
          {route.name === 'post' && <PostView id={route.id} />}
          {route.name === 'species' && <SpeciesIndex />}
          {route.name === 'speciesDetail' && <SpeciesDetail classId={route.classId} />}
          {route.name === 'rankings' && <Rankings />}
          {route.name === 'identify' && <Identify />}
        </main>
      </div>
      <TabBar route={route} />
    </StoreProvider>
  )
}
