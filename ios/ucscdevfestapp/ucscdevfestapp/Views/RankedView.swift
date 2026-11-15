//
//  RankedView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Rankings view — identified sightings ranked by the model's photo rating
/// (65% photo quality, 35% identification confidence). Uncertain IDs aren't ranked.
/// Figma: centered card with photo, name, and rank; cards stacked below.
struct RankedView: View {
    @Environment(SightingStore.self) private var store
    @State private var group: AnimalGroup? = nil

    private var ranked: [Sighting] {
        store.sightings
            .filter { $0.rating != nil && (group == nil || $0.primary?.group == group) }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, sighting in
                        NavigationLink(value: sighting.id) {
                            RankedCard(sighting: sighting, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                            .accessibilityIdentifier("ranked-" + sighting.id)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Best photos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $group) {
                            Text("Everything").tag(AnimalGroup?.none)
                            ForEach(AnimalGroup.allCases) { g in
                                Text(g.label).tag(AnimalGroup?.some(g))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease")
                    }
                }
            }
            .navigationDestination(for: Sighting.ID.self) { id in
                SightingDetailView(id: id)
            }
        }
    }
}

// MARK: - Ranked Card

/// A single ranked card.
/// Figma: photo on top, separator, rank, name and rating below.
struct RankedCard: View {
    @Environment(SightingStore.self) private var store
    let sighting: Sighting
    let rank: Int

    var body: some View {
        VStack(spacing: 0) {
            Color.canopy
                .frame(height: rank == 1 ? 260 : 200)
                .overlay { PhotoImage(source: store.photoSource(sighting)) }
                .clipped()

            HStack(spacing: 14) {
                Text("#\(rank)")
                    .font(rank <= 3 ? .wTitle : .wHeading)
                    .monospacedDigit()
                    .foregroundStyle(rank <= 3 ? Color.redwood : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sighting.title).font(.headline).lineLimit(1)
                    if sighting.title != sighting.speciesLabel {
                        Text(sighting.speciesLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("\(sighting.author), \(sighting.place)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                RatingView(rating: sighting.rating)
            }
            .padding()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RankedView().environment(SightingStore())
}
