//
//  MapTabView.swift
//  ucscdevfestapp
//
//  Map of every sighting that has a location. Tap a pin to preview it, tap the
//  preview to open the post. Google Maps when a key is configured, Apple Maps otherwise.
//

import SwiftUI
import MapKit
import GoogleMaps

struct MapTabView: View {
    @Environment(SightingStore.self) private var store
    @State private var selectedID: String?

    private var located: [Animal] {
        store.animals.filter(\.hasLocation)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if AppConfig.googleMapsAPIKey.isEmpty {
                    AppleSightingsMap(animals: located, selectedID: $selectedID)
                } else {
                    GoogleSightingsMap(animals: located, selectedID: $selectedID)
                        .ignoresSafeArea(edges: .top)
                }

                if let id = selectedID, let animal = store.animal(id: id) {
                    NavigationLink(value: animal.id) {
                        MapPreviewCard(animal: animal)
                    }
                    .buttonStyle(.plain)
                    .padding()
                } else if located.isEmpty {
                    Text(store.errorMessage ?? "No sightings with a location yet")
                        .font(.subheadline)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding()
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                AnimalDetailView(animalID: id)
            }
        }
    }
}

/// Small card shown above the tab bar for the selected pin.
private struct MapPreviewCard: View {
    let animal: Animal

    var body: some View {
        HStack(spacing: 12) {
            RemotePhoto(url: animal.imageURL, symbolSize: 20)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(animal.name)
                    .font(.headline)
                Text(animal.species)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(animal.ratingText, systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Google Maps

private struct GoogleSightingsMap: UIViewRepresentable {
    let animals: [Animal]
    @Binding var selectedID: String?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: AppConfig.campusLatitude, longitude: AppConfig.campusLongitude, zoom: 14
        )
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.settings.compassButton = true
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let ids = animals.map(\.id)
        guard ids != coordinator.shownIDs else { return }
        coordinator.shownIDs = ids
        mapView.clear()
        var bounds = GMSCoordinateBounds()
        for animal in animals {
            guard let latitude = animal.latitude, let longitude = animal.longitude else { continue }
            let position = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let marker = GMSMarker(position: position)
            marker.title = animal.name
            marker.snippet = animal.species
            marker.userData = animal.id
            marker.map = mapView
            bounds = bounds.includingCoordinate(position)
        }
        if animals.count > 1 {
            mapView.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: 60))
        } else if let only = animals.first, let latitude = only.latitude, let longitude = only.longitude {
            mapView.camera = GMSCameraPosition(latitude: latitude, longitude: longitude, zoom: 15)
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleSightingsMap
        var shownIDs: [String] = []

        init(_ parent: GoogleSightingsMap) { self.parent = parent }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            parent.selectedID = marker.userData as? String
            return false   // keep the default behaviour: centre the pin and show its title
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.selectedID = nil
        }
    }
}

// MARK: - Apple Maps fallback (no Google key configured)

private struct AppleSightingsMap: View {
    let animals: [Animal]
    @Binding var selectedID: String?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            ForEach(animals) { animal in
                if let latitude = animal.latitude, let longitude = animal.longitude {
                    Marker(
                        animal.name,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    )
                    .tag(animal.id)
                }
            }
        }
        .onChange(of: animals.map(\.id)) { position = .automatic }
    }
}
