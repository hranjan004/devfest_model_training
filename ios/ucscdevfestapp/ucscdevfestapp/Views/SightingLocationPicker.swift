import MapKit
import SwiftUI

/// A user-chosen sighting location. It never asks for or reads the device location.
struct SightingLocationPicker: View {
    let title: String
    @Binding var coordinate: CLLocationCoordinate2D
    @Binding var isMarked: Bool
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                Marker(title, coordinate: coordinate).tint(Color.redwood)
            }
            .mapStyle(.standard(elevation: .flat))
            .onTapGesture { point in
                guard let tapped = proxy.convert(point, from: .local),
                      CLLocationCoordinate2DIsValid(tapped) else { return }
                coordinate = tapped
                isMarked = true
            }
        }
        .onAppear { recenter() }
        .onChange(of: coordinate.latitude) { recenter() }
        .onChange(of: coordinate.longitude) { recenter() }
    }

    private func recenter() {
        position = .region(MKCoordinateRegion(center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
    }
}
