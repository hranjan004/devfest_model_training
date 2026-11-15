//
//  Prediction.swift
//  ucscdevfestapp
//
//  Mirrors the `/v2/predict` response of the FastAPI service in
//  hranjan004/devfest_model_training (`PredictionResponse.to_v2_dict()` in src/wildlife/schemas.py).
//  Unknown keys are ignored, so the app keeps decoding if the API adds fields.
//

import Foundation

/// What the model concluded about one detected animal (or the whole photo).
enum PredictionStatus: String, Codable, Hashable {
    /// Confident enough to name the species.
    case identified
    /// Found an animal but the best guess is under the confidence bar.
    case uncertain
    /// An animal, but not one of the 20 campus species.
    case unsupported
    /// No wild animal found (people, pets and cars are skipped on purpose).
    case noAnimal = "no_animal"
}

struct PredictedSpecies: Codable, Hashable {
    let classId: String
    let commonName: String
    let scientificName: String
    let group: AnimalGroup

    enum CodingKeys: String, CodingKey {
        case classId = "class_id", commonName = "common_name", scientificName = "scientific_name", group
    }
}

struct TopCandidate: Codable, Hashable {
    let classId: String
    let probability: Double

    enum CodingKeys: String, CodingKey {
        case classId = "class_id", probability
    }

    var species: Species? { Species.byId[classId] }
}

/// Photo-quality scores, each 0–100.
struct PhotoQuality: Codable, Hashable {
    let overall: Int
    let sharpness: Int
    let visibility: Int
    let exposure: Int
    let resolution: Int
    let composition: Int
}

/// One animal found by MegaDetector and named (or not) by BioCLIP 2.
struct Detection: Codable, Hashable {
    /// x1, y1, x2, y2 in original-image pixels.
    let box: [Double]
    let boxSource: String
    let detectorConfidence: Double
    let status: PredictionStatus
    let species: PredictedSpecies?
    let confidenceCalibrated: Double?
    let top3: [TopCandidate]
    let quality: PhotoQuality
    /// 0–100: 65% photo quality, 35% identification confidence. Nil when not identified.
    let rating: Int?

    enum CodingKeys: String, CodingKey {
        case box, status, species, quality, rating
        case boxSource = "box_source"
        case detectorConfidence = "detector_confidence"
        case confidenceCalibrated = "confidence_calibrated"
        case top3 = "top_3"
    }

    var isWholeImage: Bool { boxSource == "full_image" }

    /// Best guess even when the model won't commit to it.
    var topGuess: Species? { top3.first?.species }

    /// The group to colour this detection by: its species, else its best guess.
    var group: AnimalGroup? { species?.group ?? topGuess?.group }

    /// The label shown on the photo and as the post title.
    var label: String {
        switch status {
        case .identified: return species?.commonName ?? "Identified"
        case .uncertain:
            if let guess = topGuess { return "Possibly \(guess.commonName)" }
            return "Not sure yet"
        case .unsupported: return "Outside the trained classes"
        case .noAnimal: return "No animal found"
        }
    }
}

struct PredictionResponse: Codable, Hashable {
    let status: PredictionStatus
    let detections: [Detection]
    let primaryIndex: Int?
    let modelVersion: String
    let detectorVersion: String
    let explanation: String?
    /// Set on bundled sightings: the date their prediction was recorded from the live API.
    let recordedOn: String?

    enum CodingKeys: String, CodingKey {
        case status, detections, explanation
        case primaryIndex = "primary_index"
        case modelVersion = "model_version"
        case detectorVersion = "detector_version"
        case recordedOn = "recorded_on"
    }

    var primary: Detection? {
        if let i = primaryIndex, detections.indices.contains(i) { return detections[i] }
        return detections.first
    }
}
