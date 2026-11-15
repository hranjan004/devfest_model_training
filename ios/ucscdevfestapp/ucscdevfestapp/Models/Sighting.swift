//
//  Sighting.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//  Replaces the earlier `Animal` sample model: a post is a photo plus what the model found in it.
//

import Foundation

struct Comment: Codable, Hashable, Identifiable {
    var id = UUID()
    var author: String
    var text: String
    var date: Date
}

/// One post in the feed: a photo, where and when it was taken, and the model's prediction.
struct Sighting: Codable, Hashable, Identifiable {
    var id: String
    /// Remote photo (bundled iNaturalist sightings).
    var imageURL: URL?
    /// File name in the app's Documents folder (your own posts).
    var localImageFile: String?
    /// Original pixel size; detection boxes are in these coordinates.
    var width: Double
    var height: Double
    var author: String
    var attribution: String?
    var sourceURL: URL?
    var observedOn: String
    var latitude: Double
    var longitude: Double
    var place: String
    var prediction: PredictionResponse
    var likes: Int
    var liked: Bool = false
    var comments: [Comment] = []
    // Optional fields preserve decoding of saved posts from earlier app versions.
    var name: String? = nil
    var notes: String? = nil
    var locationIsPrecise: Bool? = nil
    var bundledImageFile: String? = nil

    var isMine: Bool { id.hasPrefix("mine-") }
    var primary: Detection? { prediction.primary }
    var speciesLabel: String { primary?.label ?? "No animal found" }
    var title: String {
        let named = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return named.isEmpty ? speciesLabel : named
    }
    var rating: Int? { primary?.rating }

    var observedDate: Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: observedOn)
    }

    /// Photo credit, spelling out CC0 when iNaturalist reports "no rights reserved".
    var credit: String? {
        guard let attribution else { return nil }
        if attribution.lowercased().hasPrefix("no rights") { return "Photo by \(author), no rights reserved (CC0)" }
        return "Photo \(attribution)"
    }
}

// MARK: - Bundled sightings

/// The shape of Resources/sightings_seed.json: 40 CC0/CC-BY research-grade iNaturalist
/// observations near UCSC, each with real `/v2/predict` output (MegaDetector V6 + BioCLIP 2)
/// recorded by web/scripts/record_seed_predictions.py in the model repo.
/// Locations are rounded to ~1 km; street addresses were removed from `place`.
private struct SeedSighting: Decodable {
    let id: String
    let image: URL?
    let name: String?
    let notes: String?
    let bundledImageFile: String?
    let attribution: String
    let source: URL
    let observedOn: String
    let lat: Double
    let lng: Double
    let place: String
    let observer: String
    let width: Double
    let height: Double
    let prediction: PredictionResponse

    enum CodingKeys: String, CodingKey {
        case id, image, attribution, source, lat, lng, place, observer, width, height, prediction, name, notes, bundledImageFile
        case observedOn = "observed_on"
    }
}

extension Sighting {
    static let bundled: [Sighting] = {
        let original = Bundle.main.decode([SeedSighting].self, from: "sightings_seed.json") ?? []
        let named = Bundle.main.decode([SeedSighting].self, from: "named_sightings_seed.json") ?? []
        let seeds = original + named
        return seeds.map { s in
            Sighting(
                id: s.id, imageURL: s.image, localImageFile: nil, width: s.width, height: s.height,
                author: s.observer, attribution: s.attribution, sourceURL: s.source, observedOn: s.observedOn,
                latitude: s.lat, longitude: s.lng, place: s.place, prediction: s.prediction,
                likes: stableLikes(s.id), name: s.name, notes: s.notes, locationIsPrecise: false, bundledImageFile: s.bundledImageFile
            )
        }
    }()

    /// Demo like counts that stay the same between launches.
    private static func stableLikes(_ id: String) -> Int {
        id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 997 } % 60
    }
}
