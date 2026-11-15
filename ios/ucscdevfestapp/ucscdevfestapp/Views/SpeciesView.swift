//
//  SpeciesView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Species browser — 2-column grid of species cards.
/// Figma: each card has a photo area and species name label,
/// laid out in a 2×3 grid. Lists every species the model can identify.
struct SpeciesView: View {
    @Environment(SightingStore.self) private var store

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.species.isEmpty {
                    FeedStatusView(emptyTitle: "No species", emptyMessage: "The server returned no species list.")
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.species) { info in
                            NavigationLink(value: info) {
                                SpeciesCard(info: info)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Species")
            .navigationDestination(for: SpeciesInfo.self) { info in
                SpeciesDetailList(info: info)
            }
            .navigationDestination(for: String.self) { id in
                AnimalDetailView(animalID: id)
            }
        }
    }
}

// MARK: - Species Card

/// A single card in the species grid.
/// Figma: photo placeholder on top, species name label below.
struct SpeciesCard: View {
    let info: SpeciesInfo

    var body: some View {
        VStack(spacing: 0) {
            RemotePhoto(url: info.cardImageURL, placeholderSymbol: info.symbolName, symbolSize: 32)
                .frame(height: 150)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.commonName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(info.sightingCount == 1 ? "1 sighting" : "\(info.sightingCount) sightings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Species Detail List

/// Shows all animals of a given species.
struct SpeciesDetailList: View {
    @Environment(SightingStore.self) private var store
    let info: SpeciesInfo

    private var animals: [Animal] {
        store.sorted(by: .newest).filter { $0.classId == info.classId }
    }

    var body: some View {
        List {
            if let reference = info.referenceImageURL {
                Section {
                    RemotePhoto(url: reference, placeholderSymbol: info.symbolName)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(info.referenceCredit ?? "")
                }
            }

            Section {
                if animals.isEmpty {
                    Text("Nobody has posted a \(info.commonName.lowercased()) yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(animals) { animal in
                    NavigationLink(value: animal.id) {
                        HStack(spacing: 12) {
                            RemotePhoto(url: animal.imageURL, symbolSize: 20)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading) {
                                Text(animal.name)
                                    .font(.headline)
                                Text(animal.species)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(info.scientificName).italic().textCase(nil)
            }
        }
        .navigationTitle(info.commonName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SpeciesView()
        .environment(SightingStore())
}
