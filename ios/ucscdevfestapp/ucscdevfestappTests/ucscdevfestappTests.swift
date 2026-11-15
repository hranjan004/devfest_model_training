//
//  ucscdevfestappTests.swift
//  ucscdevfestappTests
//
//  Created by Dean Mcculloh on 11/14/26.
//

import Foundation
import Testing
import UIKit
@testable import ucscdevfestapp

struct DataTests {
    @Test func bundledSpeciesMatchTheModel() {
        #expect(Species.all.count == 34)
        #expect(Set(Species.all.map(\.classId)).count == 34)
        #expect(Species.all.filter { $0.group == .bird }.count == 10)
        #expect(Species.byId["I01"] != nil)
        #expect(Species.byId["T07"] != nil)
        #expect(Species.byId["G06"] != nil)
        #expect(Set(Species.all.map(\.group)).count == 7)
    }

    @Test func bundledSightingsDecodeWithRealPredictions() {
        let s = Sighting.bundled
        #expect(s.count == 61)
        #expect(s.allSatisfy { $0.width > 0 && $0.height > 0 && $0.imageURL != nil || $0.bundledImageFile != nil })
        #expect(s.allSatisfy { $0.prediction.recordedOn != nil })
        // Every box sits inside its photo.
        for sighting in s {
            for d in sighting.prediction.detections {
                #expect(d.box.count == 4)
                #expect(d.box[2] <= sighting.width + 1 && d.box[3] <= sighting.height + 1)
            }
        }
    }

    @Test func noStreetAddressesInPlaces() {
        let streetish = /^\d|\b(St|Dr|Rd|Way|Blvd|Ave)\b/
        #expect(Sighting.bundled.allSatisfy { $0.place.firstMatch(of: streetish) == nil })
    }
}

struct LabelTests {
    private func detection(_ status: PredictionStatus, species: String? = nil, top: String = "M07") -> Detection {
        let sp = species.flatMap { Species.byId[$0] }.map {
            PredictedSpecies(classId: $0.classId, commonName: $0.commonName, scientificName: $0.scientificName, group: $0.group)
        }
        return Detection(
            box: [0, 0, 10, 10], boxSource: "megadetector_v6", detectorConfidence: 0.9, status: status,
            species: sp, confidenceCalibrated: sp == nil ? nil : 0.8,
            top3: [TopCandidate(classId: top, probability: 0.6)],
            quality: PhotoQuality(overall: 80, sharpness: 80, visibility: 80, exposure: 80, resolution: 80, composition: 80),
            rating: sp == nil ? nil : 80
        )
    }

    @Test func labelsFollowTheModelStatus() {
        #expect(detection(.identified, species: "M03").label == "Bobcat")
        #expect(detection(.uncertain).label == "Possibly California ground squirrel")
        #expect(detection(.unsupported).label == "Outside the trained classes")
        #expect(detection(.noAnimal).label == "No animal found")
    }

    @Test func uncertainDetectionsTakeTheirGuessGroup() {
        #expect(detection(.uncertain, top: "B05").group == .bird)
    }

    @Test func v2ResponseDecodes() throws {
        let json = """
        {"status":"uncertain","detections":[{"box":[1,2,3,4],"box_source":"megadetector_v6","detector_confidence":0.9,
        "status":"uncertain","species":null,"confidence_calibrated":null,"top_3":[{"class_id":"M06","probability":0.5}],
        "quality":{"overall":84,"sharpness":86,"visibility":65,"exposure":90,"resolution":95,"composition":92},"rating":null}],
        "primary_index":0,"model_version":"species-v2.0-t1-bioclip2","detector_version":"md6","crop_version":"crop-v1",
        "unknown_future_field":true}
        """
        let r = try JSONDecoder().decode(PredictionResponse.self, from: Data(json.utf8))
        #expect(r.primary?.label == "Possibly Striped skunk")
        #expect(r.recordedOn == nil)
    }
}

struct SortAndDateTests {
    @Test func bestPhotosPutsUnratedLast() {
        let sorted = SortOption.topRated.sorted(Sighting.bundled)
        let ratings = sorted.map { $0.rating ?? -1 }
        #expect(ratings == ratings.sorted(by: >))
    }

    @Test func dayAgoUsesWholeDays() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 8))!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!
        let threeDays = cal.date(from: DateComponents(year: 2026, month: 11, day: 12))!
        #expect(SightingPostCard.dayAgo(today, now: now, calendar: cal) == "today")
        #expect(SightingPostCard.dayAgo(threeDays, now: now, calendar: cal) == "3 days ago")
    }
}

@MainActor
struct StoreTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func likesAndPostsPersistButBundledPostsAreNotDuplicated() throws {
        let dir = tempDir()
        let store = SightingStore(documents: dir)
        let first = store.sightings[0]
        store.toggleLike(first.id)
        let prediction = try #require(Sighting.bundled.first?.prediction)
        store.post(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), size: CGSize(width: 10, height: 10),
                   prediction: prediction, spot: CampusSpot.all[0])

        let reloaded = SightingStore(documents: dir)
        #expect(reloaded.sightings.count == Sighting.bundled.count + 1)
        #expect(reloaded.sightings.filter(\.isMine).count == 1)
        #expect(reloaded.sighting(id: first.id)?.liked == true)
    }
}

@MainActor
struct ReferenceProvenanceTests {
    @Test func referenceCreditSurvivesImagePreparationAndStoreReload() throws {
        let species = try #require(Species.byId["I01"])
        let source = try #require(species.referencePhotoURL)
        let credit = try #require(species.referenceCredit)
        let image = try #require(UIImage(contentsOfFile: source.path))
        let shot = try #require(IdentifyView.Shot(image, referenceCredit: credit))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prediction = try #require(Sighting.bundled.first?.prediction)
        let store = SightingStore(bundled: [], documents: directory)
        let posted = store.post(jpeg: shot.jpeg, size: shot.image.size, prediction: prediction,
                                spot: CampusSpot.all[0], referenceCredit: shot.referenceCredit)
        let reloaded = SightingStore(bundled: [], documents: directory)
        let saved = try #require(reloaded.sighting(id: posted.id))
        #expect(saved.sourceURL == credit.observationURL)
        #expect(saved.credit?.contains(credit.photographer) == true)
        #expect(saved.credit?.contains(credit.license) == true)
        #expect(saved.credit?.contains("resized reference photo") == true)
        let savedPhoto = try #require(reloaded.localImageURL(saved))
        #expect(UIImage(contentsOfFile: savedPhoto.path) != nil)
    }
}
