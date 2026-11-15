//
//  SightingDetailView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI
import MapKit

/// Detail view for a single sighting.
/// Figma: "back to homepage" button, name (species) header,
/// large photo, map showing sighting location, comments/ratings bar.
struct SightingDetailView: View {
    @Environment(SightingStore.self) private var store
    let id: Sighting.ID
    @State private var selected: Int?
    @State private var draft = ""
    @FocusState private var commenting: Bool

    var body: some View {
        if let sighting = store.sighting(id: id) {
            content(sighting)
        } else {
            ContentUnavailableView("This post isn’t here anymore", systemImage: "photo.badge.exclamationmark")
        }
    }

    private func content(_ s: Sighting) -> some View {
        let dets = s.prediction.detections
        let d = selected.flatMap { dets.indices.contains($0) ? dets[$0] : nil } ?? s.primary
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    DetectionPhotoView(
                        source: store.photoSource(s), width: s.width, height: s.height, detections: dets,
                        selected: dets.count > 1 ? (selected ?? s.prediction.primaryIndex ?? 0) : nil,
                        onSelect: dets.count > 1 ? { selected = $0 } : nil,
                        primaryIndex: s.prediction.primaryIndex
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if dets.count > 1 {
                        Text("\(dets.count) animals found. Tap a box to see each one.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let credit = s.credit {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit + ".")
                            if let url = s.sourceURL { Link("View the iNaturalist observation", destination: url) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.wDisplay)
                            if s.title != (d?.label ?? s.speciesLabel) {
                                Text(d?.label ?? s.speciesLabel).font(.headline).foregroundStyle(.secondary)
                            }
                            if let sp = d?.species, d?.status == .identified {
                                Text(sp.scientificName).italic().foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 12)
                        RatingView(rating: d?.rating, large: true)
                    }
                    Text("Seen by \(s.author) near \(s.place).").foregroundStyle(.secondary)
                    if let notes = s.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(notes).font(.body)
                    }
                    if let habitat = (d?.species?.classId ?? d?.topGuess?.classId).flatMap({ Species.byId[$0]?.campusHabitat }), !habitat.isEmpty {
                        Text("On campus: \(habitat.lowercased()).").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        GroupChip(group: d?.group)
                        Text(modelNote(s)).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let d, !d.top3.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("How sure the model is")
                        TopThreeView(detection: d)
                    }
                }
                if let d {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading("Photo quality \(d.quality.overall)")
                        if d.isWholeImage { Text("Image-based estimates, independent of the species label.").font(.caption).foregroundStyle(.secondary) }
                        QualityView(quality: d.quality)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading("Where")
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                    )), interactionModes: []) {
                        if s.locationIsPrecise == true {
                            Marker(s.title, coordinate: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude))
                                .tint(Color.redwood)
                        } else {
                            MapCircle(center: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude), radius: 600)
                                .foregroundStyle(Color.slug.opacity(0.35))
                                .stroke(Color.redwood, lineWidth: 2)
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(s.locationIsPrecise == true ? "Location marked by the person who posted this sighting." : "Shown within about a kilometre to protect the animal and the photographer.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                comments(s)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(s.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { commenting = false }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleLike(s.id) } label: {
                    Label(s.liked ? "Unlike" : "Like", systemImage: s.liked ? "heart.fill" : "heart")
                }
                .tint(s.liked ? .redwood : .primary)
            }
        }
    }

    private func comments(_ s: Sighting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Comments")
            if s.comments.isEmpty {
                Text("No comments yet. Say what you noticed.").foregroundStyle(.secondary)
            }
            ForEach(s.comments) { c in
                (Text(c.author).bold() + Text("  ") + Text(c.text))
            }
            HStack {
                TextField("Add a comment", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("commentField")
                    .focused($commenting)
                    .submitLabel(.send)
                    .onSubmit(send)
                Button("Post", action: send)
                    .accessibilityIdentifier("postComment")
                    .buttonStyle(.borderedProminent)
                    .tint(.canopy)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func send() {
        store.addComment(draft, to: id)
        draft = ""
        commenting = false
    }

    private func modelNote(_ s: Sighting) -> String {
        if let day = s.prediction.recordedOn { return "Real model output (\(s.prediction.modelVersion)), recorded \(day)." }
        return "Whole-photo classification by \(s.prediction.modelVersion)."
    }
}

#Preview {
    NavigationStack {
        SightingDetailView(id: Sighting.bundled[0].id)
    }
    .environment(SightingStore())
}
