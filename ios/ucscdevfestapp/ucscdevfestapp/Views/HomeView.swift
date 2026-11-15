//
//  HomeView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Home feed — Instagram-style vertical scroll of animal posts.
/// Figma: sorting options bar at top, photo card, comments/ratings section, bottom tab bar.
struct HomeView: View {
    @Environment(SightingStore.self) private var store
    @State private var sortOption: SortOption = .newest
    @State private var showingNewSighting = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.animals.isEmpty {
                    FeedStatusView()
                        .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.sorted(by: sortOption)) { animal in
                            NavigationLink(value: animal.id) {
                                AnimalPostCard(animal: animal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingNewSighting = true
                    } label: {
                        Label("New Sighting", systemImage: "camera.fill")
                    }
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "line.3.horizontal.decrease")
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                AnimalDetailView(animalID: id)
            }
            .sheet(isPresented: $showingNewSighting) {
                NewSightingView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

// MARK: - Post Card

/// A single post card in the home feed.
/// Figma layout: large photo area → comments/ratings bar at bottom.
struct AnimalPostCard: View {
    let animal: Animal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo area
            RemotePhoto(url: animal.imageURL)
                .frame(height: 350)

            // Info / comments-ratings bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(animal.name)
                        .font(.headline)
                    Text("(\(animal.species))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Label(animal.ratingText, systemImage: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    Label("\(animal.commentCount)", systemImage: "bubble.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemBackground))

            Divider()
        }
    }
}

#Preview {
    HomeView()
        .environment(SightingStore())
}
