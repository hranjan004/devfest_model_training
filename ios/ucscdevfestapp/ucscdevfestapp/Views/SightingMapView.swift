//
//  SightingMapView.swift
//  ucscdevfestapp
//
//  Google Map with one pin. Used on the detail screen to show where an animal was
//  seen, and on the new sighting screen to choose the spot (tap the map to move the pin).
//  Falls back to Apple Maps when no Google Maps key is configured.
//

import SwiftUI
import MapKit
import GoogleMaps

struct SightingMapView: View {
    let title: String
    @Binding var coordinate: CLLocationCoordinate2D
    var allowsPicking = false

    var body: some View {
        if AppConfig.googleMapsAPIKey.isEmpty {
            AppleFallbackMap(title: title, coordinate: $coordinate, allowsPicking: allowsPicking)
        } else {
            GoogleMapRepresentable(title: title, coordinate: $coordinate, allowsPicking: allowsPicking)
        }
    }
}

extension SightingMapView {
    /// Read-only map for a fixed location.
    init(title: String, latitude: Double, longitude: Double) {
        self.init(
            title: title,
            coordinate: .constant(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        )
    }
}

// MARK: - Google Maps

private struct GoogleMapRepresentable: UIViewRepresentable {
    let title: String
    @Binding var coordinate: CLLocationCoordinate2D
    let allowsPicking: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(target: coordinate, zoom: 16)
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.settings.compassButton = true
        mapView.settings.scrollGestures = true
        mapView.settings.zoomGestures = true
        context.coordinator.marker.map = mapView
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        let marker = context.coordinator.marker
        marker.title = title
        let moved = marker.position.latitude != coordinate.latitude
            || marker.position.longitude != coordinate.longitude
        marker.position = coordinate
        if moved {
            mapView.animate(toLocation: coordinate)
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapRepresentable
        let marker = GMSMarker()

        init(_ parent: GoogleMapRepresentable) {
            self.parent = parent
            marker.position = parent.coordinate
            marker.title = parent.title
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            guard parent.allowsPicking else { return }
            parent.coordinate = coordinate
        }
    }
}

// MARK: - Apple Maps fallback (no Google key configured)

private struct AppleFallbackMap: View {
    let title: String
    @Binding var coordinate: CLLocationCoordinate2D
    let allowsPicking: Bool
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                Marker(title, coordinate: coordinate)
            }
            .onTapGesture { point in
                guard allowsPicking, let tapped = proxy.convert(point, from: .local) else { return }
                coordinate = tapped
            }
        }
        .onAppear { position = .region(region) }
        .onChange(of: coordinate.latitude) { position = .region(region) }
        .onChange(of: coordinate.longitude) { position = .region(region) }
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }
}
