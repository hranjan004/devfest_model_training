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
    case topRated = "Top Rated"
    case mostComments = "Most Comments"
    case alphabetical = "A–Z"

    var id: String { rawValue }
}
