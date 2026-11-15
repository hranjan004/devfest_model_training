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
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(sortOption.sorted(store.sightings)) { sighting in
                        SightingPostCard(sighting: sighting)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("coy")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("CoyMark").resizable().scaledToFit().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 7))
                        Text("coy").font(.wTitle)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
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
            .navigationDestination(for: Sighting.ID.self) { id in
                SightingDetailView(id: id)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

// MARK: - Post Card

/// A single post card in the home feed.
/// Figma layout: author row → large photo → name, rating, likes/comments bar.
struct SightingPostCard: View {
    @Environment(SightingStore.self) private var store
    let sighting: Sighting

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(String(sighting.author.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(sighting.isMine ? Color.redwood : Color.canopy, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sighting.author).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)

            NavigationLink(value: sighting.id) {
                DetectionPhotoView(
                    source: store.photoSource(sighting),
                    width: sighting.width, height: sighting.height,
                    detections: sighting.prediction.detections,
                    primaryIndex: sighting.prediction.primaryIndex
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sighting-" + sighting.id)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    NavigationLink(value: sighting.id) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sighting.title).font(.wTitle).multilineTextAlignment(.leading)
                            if sighting.title != sighting.speciesLabel {
                                Text(sighting.speciesLabel).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let sp = sighting.primary?.species, sighting.primary?.status == .identified {
                                Text(sp.scientificName).font(.subheadline).italic().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 12)
                    RatingView(rating: sighting.rating)
                }

                HStack(spacing: 16) {
                    GroupChip(group: sighting.primary?.group)
                    Button {
                        store.toggleLike(sighting.id)
                    } label: {
                        Label("\(sighting.likes)", systemImage: sighting.liked ? "heart.fill" : "heart")
                            .monospacedDigit()
                    }
                    .tint(sighting.liked ? .redwood : .secondary)
                    .accessibilityLabel(sighting.liked ? "Unlike, \(sighting.likes) likes" : "Like, \(sighting.likes) likes")
                    NavigationLink(value: sighting.id) {
                        Label("\(sighting.comments.count)", systemImage: "bubble.right").monospacedDigit()
                    }
                    .tint(.secondary)
                    .accessibilityLabel("\(sighting.comments.count) comments")
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var subtitle: String {
        guard let date = sighting.observedDate else { return sighting.place }
        return "\(sighting.place), \(Self.dayAgo(date))"
    }

    /// Observation dates have day precision, so say "today", not "8 hours ago".
    static func dayAgo(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<30: return "\(days) days ago"
        default: return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

#Preview {
    HomeView().environment(SightingStore())
}
