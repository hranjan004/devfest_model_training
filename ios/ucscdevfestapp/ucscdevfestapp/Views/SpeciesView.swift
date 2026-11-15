//
//  SpeciesView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Species browser — 2-column grid of the 34 trained classes the model knows, grouped.
/// Figma: each card has a photo area and species name label, laid out in a 2-column grid.
struct SpeciesView: View {
    @Environment(SightingStore.self) private var store

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("All 34 trained classes: mammals, birds, slugs, trees, insects and other arthropods.")
                        .foregroundStyle(.secondary)
                    ForEach(AnimalGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Circle().fill(Color.group(group)).frame(width: 10, height: 10)
                                Text(group.label).font(.wHeading)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(Species.all.filter { $0.group == group }) { species in
                                    NavigationLink(value: species) {
                                        SpeciesCard(species: species)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("species-" + species.classId)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Species")
            .navigationDestination(for: Species.self) { species in
                SpeciesDetailList(species: species)
            }
            .navigationDestination(for: Sighting.ID.self) { id in
                SightingDetailView(id: id)
            }
        }
    }
}

// MARK: - Species Card

/// A single card in the species grid.
/// Figma: photo on top, species name label below.
struct SpeciesCard: View {
    @Environment(SightingStore.self) private var store
    let species: Species

    var body: some View {
        let count = store.sightings(of: species).count
        VStack(alignment: .leading, spacing: 0) {
            Color.canopy
                .aspectRatio(4 / 5, contentMode: .fit)
                .overlay { PhotoImage(source: store.cover(for: species).flatMap { store.photoSource($0) } ?? species.referencePhotoURL.map { .file($0) }) }
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(species.commonName).font(.subheadline.weight(.bold)).lineLimit(2, reservesSpace: true)
                Text("\(count) identified \(count == 1 ? "sighting" : "sightings")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Species Detail List

/// Shows every identified sighting of a species.
struct SpeciesDetailList: View {
    @Environment(SightingStore.self) private var store
    let species: Species

    var body: some View {
        let sightings = store.sightings(of: species)
        List {
            if let photo = species.referencePhotoURL {
                Section {
                    PhotoImage(source: .file(photo))
                        .frame(height: 220)
                        .clipped()
                        .listRowInsets(EdgeInsets())
                } footer: {
                    if let credit = species.referenceCredit {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reference photo: \(credit.photographer) (\(credit.license)). Resized from iNaturalist.")
                            Link("View source observation", destination: credit.observationURL)
                        }
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(species.scientificName).italic()
                    if !species.campusHabitat.isEmpty {
                        Text("On campus: \(species.campusHabitat.lowercased()).").foregroundStyle(.secondary)
                    }
                    GroupChip(group: species.group)
                }
            }
            Section(sightings.isEmpty ? "No identified sightings yet" : "Sightings") {
                ForEach(sightings) { sighting in
                    NavigationLink(value: sighting.id) {
                        HStack(spacing: 12) {
                            Color.canopy
                                .frame(width: 60, height: 60)
                                .overlay { PhotoImage(source: store.photoSource(sighting)) }
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading) {
                                Text(sighting.title).font(.headline)
                                Text("By " + sighting.author).font(.caption).foregroundStyle(.secondary)
                                Text(sighting.place).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let r = sighting.rating { Text("\(r)").font(.wHeading.monospacedDigit()) }
                        }
                    }
                }
            }
        }
        .navigationTitle(species.commonName)
    }
}

#Preview {
    SpeciesView().environment(SightingStore())
}
