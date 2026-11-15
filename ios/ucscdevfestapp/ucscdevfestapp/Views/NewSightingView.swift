//
//  NewSightingView.swift
//  ucscdevfestapp
//
//  Take or choose a photo, let the model identify it, pin the spot on the map, and post.
//

import SwiftUI
import PhotosUI
import CoreLocation

struct NewSightingView: View {
    @Environment(SightingStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var photo: UIImage?
    @State private var jpeg: Data?

    @State private var result: IdentifyResult?
    @State private var isIdentifying = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    @State private var name = ""
    @State private var notes = ""
    @State private var includeLocation = true
    @State private var coordinate = CLLocationCoordinate2D(
        latitude: AppConfig.campusLatitude, longitude: AppConfig.campusLongitude
    )
    @State private var location = LocationProvider()
    @FocusState private var focusedField: Field?

    private enum Field { case name, notes }

    private var canPost: Bool {
        jpeg != nil && result != nil && !isPosting
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 260)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .listRowInsets(EdgeInsets())
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photo == nil ? "Choose Photo" : "Choose Another Photo", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                }

                if isIdentifying {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Identifying species")
                        }
                    }
                } else if let result {
                    Section {
                        ForEach(result.predictions, id: \.classId) { prediction in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(prediction.commonName)
                                        .fontWeight(prediction == result.top ? .semibold : .regular)
                                    Text(prediction.scientificName)
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.1f%%", prediction.probability * 100))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Species")
                    } footer: {
                        if result.lowConfidence {
                            Text("The model is not sure. It only knows 34 UCSC species, so this may be something else.")
                        }
                    }
                }

                if photo != nil {
                    Section("Details") {
                        TextField("Give it a name", text: $name)
                            .accessibilityIdentifier("sightingName")
                            .focused($focusedField, equals: .name)
                        TextField("Where and how you saw it (optional)", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("sightingNotes")
                            .focused($focusedField, equals: .notes)
                    }

                    Section {
                        Toggle("Share location", isOn: $includeLocation)
                        if includeLocation {
                            SightingMapView(
                                title: name.isEmpty ? "Sighting" : name,
                                coordinate: $coordinate,
                                allowsPicking: true
                            )
                            .frame(height: 220)
                            .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        Text("Location")
                    } footer: {
                        if includeLocation {
                            Text(location.denied
                                 ? "Location access is off. Tap the map to place the pin."
                                 : "Tap the map to move the pin.")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                        if jpeg != nil && result == nil && !isIdentifying {
                            Button("Try Again") { Task { await identify() } }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Sighting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await post() } }
                            .disabled(!canPost)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await use(image)
                    } else {
                        errorMessage = "That photo couldn't be opened."
                    }
                }
            }
            .onChange(of: location.coordinate?.latitude) {
                if let found = location.coordinate { coordinate = found }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    Task { await use(image) }
                }
                .ignoresSafeArea()
            }
            .onAppear { location.request() }
        }
    }

    private func use(_ image: UIImage) async {
        let prepared = image.preparedForUpload()
        photo = prepared.image
        jpeg = prepared.jpeg
        await identify()
    }

    private func identify() async {
        guard let jpeg else { return }
        result = nil
        errorMessage = nil
        isIdentifying = true
        defer { isIdentifying = false }
        do {
            result = try await APIClient.shared.identify(jpeg: jpeg)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func post() async {
        guard let jpeg else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let animal = try await APIClient.shared.createSighting(
                jpeg: jpeg,
                name: name.trimmingCharacters(in: .whitespaces),
                description: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: includeLocation ? coordinate.latitude : nil,
                longitude: includeLocation ? coordinate.longitude : nil
            )
            store.upsert(animal)
            dismiss()
            await store.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Helpers

private extension UIImage {
    /// Downscale to at most 1600 px on the long side and encode as JPEG for upload.
    func preparedForUpload(maxSide: CGFloat = 1600) -> (image: UIImage, jpeg: Data?) {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return (resized, resized.jpegData(compressionQuality: 0.85))
    }
}

/// System camera wrapped for SwiftUI.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
