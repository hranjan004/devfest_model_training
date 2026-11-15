import Foundation
import Testing
import UIKit
@testable import ucscdevfestapp

@MainActor
struct CoyPersistenceTests {
    @Test func namedMarkedSightingAndCommentSurviveReload() throws {
        let species = try #require(Species.byId["I01"])
        let photoURL = try #require(species.referencePhotoURL)
        let image = try #require(UIImage(contentsOfFile: photoURL.path))
        let shot = try #require(IdentifyView.Shot(image, referenceCredit: species.referenceCredit))
        let prediction = try #require(Sighting.bundled.first?.prediction)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SightingStore(bundled: [], documents: directory)
        let selected = CampusSpot(name: "Upper Campus", latitude: 37.00123, longitude: -122.06123)
        let posted = store.post(jpeg: shot.jpeg, size: shot.image.size, prediction: prediction,
                                spot: selected, referenceCredit: shot.referenceCredit,
                                name: "  Goldie  ", notes: "Near the redwoods.", locationIsPrecise: true)
        store.addComment("Spotted again today.", to: posted.id)
        store.toggleLike(posted.id)

        let reopened = SightingStore(bundled: [], documents: directory)
        let saved = try #require(reopened.sighting(id: posted.id))
        #expect(saved.name == "Goldie")
        #expect(saved.title == "Goldie")
        #expect(saved.speciesLabel == prediction.primary?.label)
        #expect(saved.notes == "Near the redwoods.")
        #expect(saved.latitude == selected.latitude && saved.longitude == selected.longitude)
        #expect(saved.locationIsPrecise == true)
        #expect(saved.comments.map(\.text) == ["Spotted again today."])
        #expect(saved.liked && saved.likes == 1)
        #expect(saved.sourceURL == shot.referenceCredit?.observationURL)
        let credit = try #require(shot.referenceCredit)
        #expect(saved.credit?.contains(credit.photographer) == true)
    }

    @Test func legacySavedSightingStillDecodesWithoutNewMetadata() throws {
        let original = try #require(Sighting.bundled.first)
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["name", "notes", "locationIsPrecise", "bundledImageFile"] { object.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Sighting.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.name == nil && legacy.notes == nil && legacy.locationIsPrecise == nil)
        #expect(legacy.title == legacy.speciesLabel)
        #expect(legacy.prediction == original.prediction)
        #expect(legacy.comments == original.comments)
    }
}
