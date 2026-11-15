//
//  RankedView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Rankings view — animals sorted by rank.
/// Figma: centered card with photo, name, and rank; second card below with another photo.
struct RankedView: View {
    @Environment(SightingStore.self) private var store
    @State private var sortOption: SortOption = .topRated

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.animals.isEmpty {
                    FeedStatusView(emptyMessage: "Rankings appear once sightings are posted and rated.")
                        .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(store.sorted(by: sortOption).enumerated()), id: \.element.id) { index, animal in
                            NavigationLink(value: animal.id) {
                                RankedCard(animal: animal, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Rankings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
        }
    }
}

// MARK: - Ranked Card

/// A single ranked animal card.
/// Figma: photo on top, dashed separator, name and rank label below.
struct RankedCard: View {
    let animal: Animal
    let rank: Int

    var body: some View {
        VStack(spacing: 0) {
            // Photo area
            RemotePhoto(url: animal.imageURL)
                .frame(height: 240)

            Divider()

            // Name and rank
            HStack {
                Text("#\(rank)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(animal.name)
                        .font(.headline)
                    Text(animal.species)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(animal.ratingText, systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            .padding()
        }
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    RankedView()
        .environment(SightingStore())
}
