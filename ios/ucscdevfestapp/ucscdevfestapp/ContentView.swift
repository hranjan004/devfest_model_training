//
//  ContentView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Root view with a TabView matching the Figma bottom tab bar:
/// Home | Species | Ranked, plus a Map tab showing where every sighting was made.
struct ContentView: View {
    @State private var store = SightingStore()

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Species", systemImage: "pawprint.fill") {
                SpeciesView()
            }
            Tab("Ranked", systemImage: "trophy.fill") {
                RankedView()
            }
            Tab("Map", systemImage: "map.fill") {
                MapTabView()
            }
        }
        .environment(store)
        .task { await store.refresh() }
    }
}

#Preview {
    ContentView()
}
