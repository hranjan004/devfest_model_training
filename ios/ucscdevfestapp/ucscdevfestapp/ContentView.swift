//
//  ContentView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Root view with a TabView matching the Figma bottom tab bar:
/// Home | Species | Identify | Ranked | Map
struct ContentView: View {
    @State private var store = SightingStore()
    @State private var tab: AppTab = .home

    enum AppTab: Hashable { case home, species, identify, ranked, map }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Species", systemImage: "pawprint.fill", value: AppTab.species) {
                SpeciesView()
            }
            Tab("Identify", systemImage: "viewfinder", value: AppTab.identify) {
                IdentifyView(onPosted: { tab = .home })
            }
            Tab("Ranked", systemImage: "trophy.fill", value: AppTab.ranked) {
                RankedView()
            }
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                MapTabView()
            }
        }
        .tint(.redwood)
        .environment(store)
    }
}

#Preview {
    ContentView()
}
