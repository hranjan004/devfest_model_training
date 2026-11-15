//
//  SightingStore.swift
//  ucscdevfestapp
//
//  Shared app state: the sightings feed and the species list, loaded from the API.
//

import Foundation
import Observation

@MainActor
@Observable
final class SightingStore {
    var animals: [Animal] = []
    var species: [SpeciesInfo] = []
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let feed = APIClient.shared.sightings()
            async let list = APIClient.shared.species()
            let (newAnimals, newSpecies) = try await (feed, list)
            animals = newAnimals
            species = newSpecies
            errorMessage = nil
            hasLoaded = true
        } catch is CancellationError {
            // A newer refresh replaced this one.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Put an updated or new sighting into the feed without a full reload.
    func upsert(_ animal: Animal) {
        if let index = animals.firstIndex(where: { $0.id == animal.id }) {
            animals[index] = animal
        } else {
            animals.insert(animal, at: 0)
        }
    }

    func animal(id: String) -> Animal? {
        animals.first { $0.id == id }
    }

    func sorted(by option: SortOption) -> [Animal] {
        switch option {
        case .newest:
            return animals.sorted { $0.createdAt > $1.createdAt }
        case .topRated:
            return animals.sorted { ($0.ratingAverage, $0.ratingCount) > ($1.ratingAverage, $1.ratingCount) }
        case .mostComments:
            return animals.sorted { $0.commentCount > $1.commentCount }
        case .alphabetical:
            return animals.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}
