//
//  SortOption.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import Foundation

/// Sorting options for the home feed and rankings.
enum SortOption: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case topRated = "Best Photos"
    case mostLiked = "Most Liked"
    case alphabetical = "A–Z"

    var id: String { rawValue }

    func sorted(_ sightings: [Sighting]) -> [Sighting] {
        switch self {
        case .newest:
            // Your own posts first, then by observation date.
            return sightings.sorted {
                if $0.isMine != $1.isMine { return $0.isMine }
                return $0.observedOn > $1.observedOn
            }
        case .topRated:
            return sightings.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .mostLiked:
            return sightings.sorted { $0.likes > $1.likes }
        case .alphabetical:
            return sightings.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}
