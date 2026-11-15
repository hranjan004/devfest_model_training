//
//  SightingStore.swift
//  ucscdevfestapp
//
//  Holds every sighting the tabs show. Your own posts, likes and comments are saved to
//  Documents/sightings_state.json; bundled sightings are rebuilt from the app bundle on launch.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SightingStore {
    private(set) var sightings: [Sighting]

    private struct Saved: Codable {
        var mine: [Sighting] = []
        var liked: [String] = []
        var comments: [String: [Comment]] = [:]
    }

    private let stateURL: URL
    private let documents: URL

    init(bundled: [Sighting] = Sighting.bundled, documents: URL? = nil) {
        let docs = documents ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.documents = docs
        self.stateURL = docs.appendingPathComponent("sightings_state.json")
        let saved = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
        sightings = (saved.mine + bundled).map { s in
            var s = s
            if !s.isMine {
                s.liked = saved.liked.contains(s.id)
                if s.liked { s.likes += 1 }
                s.comments = saved.comments[s.id] ?? []
            }
            return s
        }
    }

    func sighting(id: String) -> Sighting? { sightings.first { $0.id == id } }

    func sightings(of species: Species) -> [Sighting] {
        sightings.filter { $0.primary?.status == .identified && $0.primary?.species?.classId == species.classId }
    }

    /// A photo for the species grid: an identified sighting, else one whose best guess is this species.
    func cover(for species: Species) -> Sighting? {
        sightings(of: species).first ?? sightings.first { $0.primary?.topGuess?.classId == species.classId }
    }

    func toggleLike(_ id: String) {
        guard let i = sightings.firstIndex(where: { $0.id == id }) else { return }
        sightings[i].liked.toggle()
        sightings[i].likes += sightings[i].liked ? 1 : -1
        save()
    }

    func addComment(_ text: String, to id: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = sightings.firstIndex(where: { $0.id == id }) else { return }
        sightings[i].comments.append(Comment(author: "You", text: String(trimmed.prefix(500)), date: .now))
        save()
    }

    /// Saves the (already EXIF-free) JPEG and adds the post to the top of the feed.
    @discardableResult
    func post(jpeg: Data, size: CGSize, prediction: PredictionResponse, spot: CampusSpot, referenceCredit: ReferenceCredit? = nil, name: String = "", notes: String = "", locationIsPrecise: Bool = false) -> Sighting {
        let id = "mine-\(UUID().uuidString)"
        let file = "\(id).jpg"
        try? jpeg.write(to: documents.appendingPathComponent(file), options: .atomic)
        let day = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withFullDate])
        let sighting = Sighting(
            id: id, imageURL: nil, localImageFile: file, width: size.width, height: size.height,
            author: "You",
            attribution: referenceCredit.map { "by \($0.photographer) (\($0.license)); resized reference photo" },
            sourceURL: referenceCredit?.observationURL, observedOn: day,
            latitude: spot.latitude, longitude: spot.longitude, place: spot.name,
            prediction: prediction, likes: 0,
            name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)),
            notes: String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            locationIsPrecise: locationIsPrecise
        )
        sightings.insert(sighting, at: 0)
        save()
        return sighting
    }

    func localImageURL(_ s: Sighting) -> URL? {
        s.localImageFile.map { documents.appendingPathComponent($0) }
    }

    private func save() {
        let saved = Saved(
            mine: sightings.filter(\.isMine),
            liked: sightings.filter { !$0.isMine && $0.liked }.map(\.id),
            comments: Dictionary(uniqueKeysWithValues: sightings.filter { !$0.isMine && !$0.comments.isEmpty }.map { ($0.id, $0.comments) })
        )
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: stateURL, options: .atomic) }
    }
}

/// Where on campus a new post is pinned. Coordinates are rounded to ~1 km on purpose.
struct CampusSpot: Hashable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }

    static let all: [CampusSpot] = [
        CampusSpot(name: "East Field", latitude: 36.99, longitude: -122.05),
        CampusSpot(name: "Arboretum", latitude: 36.98, longitude: -122.06),
        CampusSpot(name: "Great Meadow", latitude: 36.98, longitude: -122.06),
        CampusSpot(name: "Porter Meadow", latitude: 36.99, longitude: -122.07),
        CampusSpot(name: "Upper Campus", latitude: 37.01, longitude: -122.07),
        CampusSpot(name: "Campus Natural Reserve", latitude: 37.00, longitude: -122.06),
    ]
}
