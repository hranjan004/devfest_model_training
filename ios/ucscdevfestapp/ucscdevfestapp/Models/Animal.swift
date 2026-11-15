//
//  Animal.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import Foundation

/// One of the model's ranked guesses for a photo.
struct SpeciesPrediction: Codable, Hashable {
    var classId: String
    var commonName: String
    var scientificName: String
    var group: String
    var probability: Double
}

/// Response of `POST /v3/identify`.
struct IdentifyResult: Codable {
    var modelVersion: String
    var top: SpeciesPrediction
    var predictions: [SpeciesPrediction]
    var lowConfidence: Bool
}

/// A single animal post in the app, as served by `GET /v3/sightings`.
struct Animal: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var description: String
    var classId: String
    var commonName: String
    var scientificName: String
    var group: String
    var confidence: Double
    var lowConfidence: Bool
    var predictions: [SpeciesPrediction]
    var latitude: Double?
    var longitude: Double?
    var createdAt: String
    var ratingAverage: Double
    var ratingCount: Int
    var commentCount: Int
    var myRating: Int?
    var imageUrl: String
    var isDemo: Bool?

    var species: String { commonName }
    var rating: Double { ratingAverage }
    var imageURL: URL? { URL(string: imageUrl, relativeTo: AppConfig.serverURL) }
    var hasLocation: Bool { latitude != nil && longitude != nil }

    var ratingText: String {
        ratingCount == 0 ? "No ratings" : String(format: "%.1f", ratingAverage)
    }

    var confidenceText: String {
        String(format: "%.1f%% match", confidence * 100)
    }
}

/// One of the 34 classes the model knows, as served by `GET /v3/species`.
struct SpeciesInfo: Identifiable, Hashable, Codable {
    var classId: String
    var commonName: String
    var scientificName: String
    var group: String
    var sightingCount: Int
    var coverImageUrl: String?
    var referenceImageUrl: String?
    var referenceCredit: String?

    var id: String { classId }
    var referenceImageURL: URL? {
        referenceImageUrl.flatMap { URL(string: $0, relativeTo: AppConfig.serverURL) }
    }
    /// Newest posted photo of this species, or the reference photo until someone posts one.
    var cardImageURL: URL? {
        coverImageUrl.flatMap { URL(string: $0, relativeTo: AppConfig.serverURL) } ?? referenceImageURL
    }

    /// Icon shown until someone posts a photo of this species.
    var symbolName: String {
        switch group {
        case "bird": return "bird.fill"
        case "tree": return "tree.fill"
        case "insect", "arthropod": return "ladybug.fill"
        case "gastropod": return "leaf.fill"
        case "small_mammal": return "hare.fill"
        default: return "pawprint.fill"
        }
    }
}

struct Comment: Identifiable, Hashable, Codable {
    var id: String
    var author: String
    var text: String
    var createdAt: String
}
