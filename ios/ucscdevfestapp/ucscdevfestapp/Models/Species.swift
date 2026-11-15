//
//  Species.swift
//  ucscdevfestapp
//
//  The 34 trained classes (runs/ucsc34_bioclip_v4/classes.json in the model repo),
//  bundled as Resources/species.json.
//

import Foundation

enum AnimalGroup: String, Codable, CaseIterable, Hashable, Identifiable {
    case largeMammal = "large_mammal"
    case smallMammal = "small_mammal"
    case bird
    case gastropod
    case tree
    case insect
    case arthropod

    var id: String { rawValue }

    var label: String {
        switch self {
        case .largeMammal: return "Large mammals"
        case .smallMammal: return "Small mammals"
        case .bird: return "Birds"
        case .gastropod: return "Slugs"
        case .tree: return "Trees"
        case .insect: return "Insects"
        case .arthropod: return "Other arthropods"
        }
    }

    var symbol: String {
        switch self {
        case .largeMammal: return "hare.fill"
        case .smallMammal: return "pawprint.fill"
        case .bird: return "bird.fill"
        case .gastropod: return "leaf.fill"
        case .tree: return "tree.fill"
        case .insect: return "ant.fill"
        case .arthropod: return "ant.fill"
        }
    }
}

struct Species: Codable, Hashable, Identifiable {
    let classId: String
    let index: Int
    let commonName: String
    let scientificName: String
    let group: AnimalGroup
    let campusHabitat: String

    var id: String { classId }

    enum CodingKeys: String, CodingKey {
        case index, group
        case classId = "class_id"
        case commonName = "common_name"
        case scientificName = "scientific_name"
        case campusHabitat = "campus_habitat"
    }

    var referencePhotoURL: URL? { Bundle.main.url(forResource: "reference_" + classId, withExtension: "jpg") }
    var referenceCredit: ReferenceCredit? { Self.referenceCredits[classId] }
    private static let referenceCredits: [String: ReferenceCredit] = Bundle.main.decode([String: ReferenceCredit].self, from: "reference_credits.json") ?? [:]

    static let all: [Species] = Bundle.main.decode([Species].self, from: "species.json") ?? []
    static let byId: [String: Species] = Dictionary(uniqueKeysWithValues: all.map { ($0.classId, $0) })
}

extension Bundle {
    func decode<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let url = url(forResource: file, withExtension: nil),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

struct ReferenceCredit: Decodable {
    let photographer: String
    let license: String
    let observationURL: URL
    enum CodingKeys: String, CodingKey {
        case photographer, license
        case observationURL = "observation_url"
    }
}
