import SwiftUI
import MapKit

/// One map joins the feed's named sightings to their full posts and comments.
struct MapTabView: View {
    @Environment(SightingStore.self) private var store
    @State private var position: MapCameraPosition = .region(Self.campus)
    @State private var selectedID: String?
    @State private var query = ""
    @FocusState private var searching: Bool

    private static let campus = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.995, longitude: -122.06),
        span: MKCoordinateSpan(latitudeDelta: 0.065, longitudeDelta: 0.065)
    )

    private var sightings: [Sighting] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.sightings.filter { s in
            s.latitude.isFinite && s.longitude.isFinite && abs(s.latitude) <= 90 && abs(s.longitude) <= 180 &&
            (text.isEmpty || s.title.localizedCaseInsensitiveContains(text) || s.speciesLabel.localizedCaseInsensitiveContains(text) || s.place.localizedCaseInsensitiveContains(text))
        }
    }
    private var selected: Sighting? { sightings.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a name, species or place", text: $query)
                        .accessibilityIdentifier("mapSearch")
                        .focused($searching)
                        .submitLabel(.search)
                        .onSubmit { searching = false }
                    if !query.isEmpty {
                        Button { query = ""; searching = false } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear map search")
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal).padding(.bottom, 10)

                Map(position: $position, selection: $selectedID) {
                    ForEach(sightings) { sighting in
                        Marker(sighting.title, coordinate: coordinate(sighting))
                            .tint(markerColor(sighting))
                            .tag(sighting.id)
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .accessibilityIdentifier("sightingsMap")
                .frame(minHeight: searching ? 120 : 220)
                .overlay(alignment: .topLeading) {
                    Text("\(sightings.count) \(sightings.count == 1 ? "sighting" : "sightings")")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
                .onChange(of: selectedID) { _, value in
                    if value != nil { searching = false }
                }
                .onChange(of: query) {
                    selectedID = nil
                    position = .automatic
                }

                if let s = selected {
                    NavigationLink(value: s.id) {
                        MapSightingPreview(sighting: s)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mapPost-" + s.id)
                    .padding(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sightings on this map").font(.wHeading)
                        Spacer()
                        Text("Tap a name to locate").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    if sightings.isEmpty {
                        Text("No matching sightings. Try another name or species.")
                            .font(.subheadline).foregroundStyle(.secondary).padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(sightings) { s in
                                    Button { select(s) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: selectedID == s.id ? "mappin.circle.fill" : "mappin.circle")
                                                .foregroundStyle(Color.redwood)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                                Text(s.speciesLabel + " · " + s.place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer()
                                            if selectedID == s.id { Image(systemName: "checkmark").foregroundStyle(Color.redwood) }
                                        }
                                        .padding(.horizontal).padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selectedID == s.id ? Color.redwood.opacity(0.08) : .clear)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("mapSighting-" + s.id)
                                }
                            }
                        }
                        .frame(height: searching ? 100 : (selected == nil ? 190 : 105))
                    }
                }
                .padding(.top, 12)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Campus") { query = ""; selectedID = nil; searching = false; position = .region(Self.campus) }
                    Button("All") { query = ""; searching = false; position = .automatic }
                }
            }
            .navigationDestination(for: Sighting.ID.self) { id in
                SightingDetailView(id: id)
            }
        }
    }

    private func markerColor(_ s: Sighting) -> Color {
        guard let group = s.primary?.group else { return .redwood }
        return Color.group(group)
    }
    private func coordinate(_ s: Sighting) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
    }
    private func select(_ s: Sighting) {
        searching = false
        selectedID = s.id
        withAnimation(.easeInOut(duration: 0.5)) {
            position = .region(MKCoordinateRegion(center: coordinate(s), span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        }
    }
}

private struct MapSightingPreview: View {
    @Environment(SightingStore.self) private var store
    let sighting: Sighting

    var body: some View {
        HStack(spacing: 12) {
            Color.canopy
                .frame(width: 70, height: 70)
                .overlay { PhotoImage(source: store.photoSource(sighting)) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(sighting.title).font(.headline).lineLimit(1)
                Text(sighting.speciesLabel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(sighting.locationIsPrecise == true ? "Marked location · Open post" : "Approximate location · Open post")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Color.redwood)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
