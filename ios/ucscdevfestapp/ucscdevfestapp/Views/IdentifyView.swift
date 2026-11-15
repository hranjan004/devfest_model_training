//
//  IdentifyView.swift
//  ucscdevfestapp
//
//  Take or choose a photo → BioCLIP-v4 classifies it →
//  confirm or correct → post. Talks to POST /v2/predict on the FastAPI service.
//

import MapKit
import PhotosUI
import SwiftUI

struct IdentifyView: View {
    var onPosted: () -> Void = {}

    @Environment(SightingStore.self) private var store
    @State private var phase: Phase = .pick
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    enum Phase {
        case pick
        case working(Shot)
        case done(Shot, PredictionResponse)
        case failed(Shot?, String)
    }

    /// A photo ready to send: downscaled and re-encoded, which also drops EXIF (including GPS).
    struct Shot {
        let image: UIImage
        let jpeg: Data
        let referenceCredit: ReferenceCredit?

        init?(_ original: UIImage, referenceCredit: ReferenceCredit? = nil) {
            self.referenceCredit = referenceCredit
            let longest = max(original.size.width, original.size.height)
            let scale = min(1, 1280 / max(longest, 1))
            let size = CGSize(width: (original.size.width * scale).rounded(), height: (original.size.height * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in original.draw(in: CGRect(origin: .zero, size: size)) }
            guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
            image = resized
            jpeg = data
        }
    }

    private var isPicking: Bool {
        if case .pick = phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch phase {
                    case .pick: pickView
                    case .working(let shot): workingView(shot)
                    case .done(let shot, let result):
                        ResultView(shot: shot, result: result, onPost: post, onRetake: reset)
                    case .failed(let shot, let message): failedView(shot, message)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Identify")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isPicking {
                        Button("New photo", action: reset)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                        await run(ui)
                    } else {
                        phase = .failed(nil, "That file couldn’t be opened as a photo.")
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { Task { await run(image) } }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Phases

    private var pickView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Take or choose a photo. BioCLIP-v4 classifies the whole image across all 34 trained wildlife and tree classes.")
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 14) {
                    BracketShape(fraction: 0.32)
                        .stroke(Color.canopy, style: StrokeStyle(lineWidth: 4, lineCap: .square))
                        .frame(width: 84, height: 84)
                    Text("Choose a photo").font(.wTitle)
                    Text("from your library").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.lichen, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("choosePhoto")

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: {
                    Label("Take a photo", systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.redwood)
            }

            Button {
                Task { await runSample() }
            } label: {
                Label("Try a sample campus photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.canopy)

            Text("Location data is removed from your photo before anything is sent.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func workingView(_ shot: Shot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(uiImage: shot.image)
                .resizable().scaledToFit()
                .opacity(0.8)
                .overlay { ScanLine() }
                .overlay {
                    BracketShape()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Identifying your photo").font(.wTitle)
            Text("BioCLIP-v4 compares your photo with the 34 trained classes.").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func failedView(_ shot: Shot?, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let shot {
                Image(uiImage: shot.image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text("That didn’t work").font(.wTitle)
            Text(message).foregroundStyle(.secondary)
            HStack {
                if let shot {
                    Button("Try again") { Task { await run(shot.image, referenceCredit: shot.referenceCredit) } }
                        .buttonStyle(.borderedProminent).tint(.redwood)
                }
                Button("Choose another photo", action: reset).buttonStyle(.bordered)
            }
        }
    }

    // MARK: Actions

    private func run(_ image: UIImage, referenceCredit: ReferenceCredit? = nil) async {
        guard let shot = Shot(image, referenceCredit: referenceCredit) else {
            phase = .failed(nil, "That photo couldn’t be prepared for upload.")
            return
        }
        phase = .working(shot)
        do {
            let result = try await WildlifeAPI.current.predict(jpeg: shot.jpeg)
            phase = .done(shot, result)
        } catch {
            phase = .failed(shot, error.localizedDescription)
        }
    }

    /// Classifies one bundled, credited reference photo through the live model.
    private func runSample() async {
        guard let species = Species.all.randomElement(),
              let url = species.referencePhotoURL,
              let ui = UIImage(contentsOfFile: url.path) else {
            phase = .failed(nil, "The sample photo could not be loaded.")
            return
        }
        await run(ui, referenceCredit: species.referenceCredit)
    }

    private func post(_ shot: Shot, _ prediction: PredictionResponse, _ spot: CampusSpot, _ name: String, _ notes: String, _ locationIsPrecise: Bool) {
        store.post(jpeg: shot.jpeg, size: shot.image.size, prediction: prediction, spot: spot, referenceCredit: shot.referenceCredit, name: name, notes: notes, locationIsPrecise: locationIsPrecise)
        reset()
        onPosted()
    }

    private func reset() {
        phase = .pick
        pickerItem = nil
    }
}

// MARK: - Result

private struct ResultView: View {
    let shot: IdentifyView.Shot
    let result: PredictionResponse
    let onPost: (IdentifyView.Shot, PredictionResponse, CampusSpot, String, String, Bool) -> Void
    let onRetake: () -> Void

    @State private var detections: [Detection]
    @State private var selected: Int
    @State private var spot = CampusSpot.all[0]
    @State private var sightingName = ""
    @State private var sightingNotes = ""
    @State private var coordinate = CLLocationCoordinate2D(latitude: CampusSpot.all[0].latitude, longitude: CampusSpot.all[0].longitude)
    @State private var locationIsPrecise = false
    @FocusState private var focusedMetadata: MetadataField?
    private enum MetadataField { case name, notes }
    @State private var correcting: CorrectionRequest?

    struct CorrectionRequest: Identifiable {
        let id = UUID()
        let initial: String?
    }

    init(shot: IdentifyView.Shot, result: PredictionResponse,
         onPost: @escaping (IdentifyView.Shot, PredictionResponse, CampusSpot, String, String, Bool) -> Void, onRetake: @escaping () -> Void) {
        self.shot = shot
        self.result = result
        self.onPost = onPost
        self.onRetake = onRetake
        _detections = State(initialValue: result.detections)
        _selected = State(initialValue: result.primaryIndex ?? 0)
    }

    private var current: PredictionResponse {
        PredictionResponse(status: detections.first?.status ?? result.status, detections: detections,
                           primaryIndex: result.primaryIndex, modelVersion: result.modelVersion,
                           detectorVersion: result.detectorVersion, explanation: result.explanation, recordedOn: nil)
    }

    var body: some View {
        if detections.isEmpty || result.status == .noAnimal {
            noAnimal
        } else {
            found
        }
    }

    private var noAnimal: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(uiImage: shot.image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("No animal found").font(.wDisplay)
            Text("The detector couldn’t find a wild animal here. People, pets and cars are skipped on purpose. If there is an animal, try a closer photo where it fills more of the frame.")
                .foregroundStyle(.secondary)
            Button("Try another photo", action: onRetake).buttonStyle(.borderedProminent).tint(.redwood)
        }
    }

    private var found: some View {
        let d = detections[min(selected, detections.count - 1)]
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                DetectionPhotoView(
                    source: .image(shot.image), width: shot.image.size.width, height: shot.image.size.height,
                    detections: detections, animate: true,
                    selected: detections.count > 1 ? selected : nil,
                    onSelect: detections.count > 1 ? { selected = $0 } : nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if detections.count > 1 {
                    Text("\(detections.count) animals found. Tap a box to see each one.").font(.footnote).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.label).font(.wDisplay)
                        if d.status == .identified, let sp = d.species {
                            Text(sp.scientificName).italic().foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    RatingView(rating: d.rating, large: true)
                }
                FlowChips(detection: d, count: detections.count)
                switch d.status {
                case .uncertain:
                    Text("The model is unsure. Review its top matches, choose a label yourself, or post the uncertain result.")
                case .unsupported:
                    Text("This photo may be outside the 34 trained classes.")
                default:
                    EmptyView()
                }
            }

            if d.status == .uncertain, !d.top3.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("Which one is it?")
                    ForEach(Array(d.top3.enumerated()), id: \.offset) { i, c in
                        Button { correcting = CorrectionRequest(initial: c.classId) } label: {
                            HStack(spacing: 12) {
                                Text(c.species?.commonName ?? c.classId).fontWeight(i == 0 ? .bold : .regular)
                                Spacer()
                                Bar(value: c.probability, color: c.species.map { Color.group($0.group) } ?? .lichen).frame(width: 90)
                                Text(String(format: "%.1f%%", c.probability * 100)).monospacedDigit().frame(width: 56, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 46)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(i == 0 ? Color.canopy : Color(.separator), lineWidth: i == 0 ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !d.top3.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading("Top matches")
                    if d.isWholeImage { Text("Model confidence is a score, not a guarantee.").font(.caption).foregroundStyle(.secondary) }
                    TopThreeView(detection: d, animate: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading("Photo quality \(d.quality.overall)")
                if d.isWholeImage { Text("Image-based estimates, independent of the species label.").font(.caption).foregroundStyle(.secondary) }
                QualityView(quality: d.quality)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeading("Your sighting")
                TextField("Name this sighting", text: $sightingName)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .accessibilityIdentifier("sightingName")
                    .focused($focusedMetadata, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedMetadata = .notes }
                TextField("Add notes about what you saw", text: $sightingNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("sightingNotes")
                    .focused($focusedMetadata, equals: .notes)

                SectionHeading("Mark the sighting")
                Picker("Campus area", selection: $spot) {
                    ForEach(CampusSpot.all) { Text($0.name).tag($0) }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("campusSpot")
                .onChange(of: spot) {
                    coordinate = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
                    locationIsPrecise = false
                }
                SightingLocationPicker(
                    title: sightingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? d.label : sightingName,
                    coordinate: $coordinate,
                    isMarked: $locationIsPrecise
                )
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityIdentifier("sightingLocationMap")
                Text(locationIsPrecise ? "Your marked spot will appear on the sightings map." : "Tap the map to mark the spot, or use the approximate campus area.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button {
                        focusedMetadata = nil
                        let markedSpot = CampusSpot(name: spot.name, latitude: coordinate.latitude, longitude: coordinate.longitude)
                        onPost(shot, current, markedSpot, sightingName, sightingNotes, locationIsPrecise)
                    } label: {
                        Text("Post sighting").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.redwood)
                    .accessibilityIdentifier("postSighting")
                    Button { correcting = CorrectionRequest(initial: nil) } label: {
                        Text(d.status == .identified ? "That’s not right" : "None of these").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).tint(.canopy)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedMetadata = nil }
            }
        }
        .sheet(item: $correcting) { req in
            CorrectionSheet(current: d.species?.classId ?? d.topGuess?.classId, initial: req.initial) { classId in
                apply(classId, to: min(selected, detections.count - 1))
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Replaces the model's label with the user's choice on this post.
    private func apply(_ classId: String, to i: Int) {
        guard let sp = Species.byId[classId] else { return }
        let d = detections[i]
        detections[i] = Detection(
            box: d.box, boxSource: d.boxSource, detectorConfidence: d.detectorConfidence, status: .identified,
            species: PredictedSpecies(classId: sp.classId, commonName: sp.commonName, scientificName: sp.scientificName, group: sp.group),
            confidenceCalibrated: nil, top3: d.top3, quality: d.quality, rating: nil
        )
    }
}

private struct FlowChips: View {
    let detection: Detection
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Label(detection.isWholeImage ? "Whole-photo prediction" : "Found \(count) \(count == 1 ? "animal" : "animals")", systemImage: "checkmark")
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
            GroupChip(group: detection.group)
        }
        .font(.footnote)
    }
}

// MARK: - Correction

private struct CorrectionSheet: View {
    let current: String?
    let initial: String?
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: String = ""
    @State private var share = true
    @State private var sendFailed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Species", selection: $choice) {
                        Text("Choose a species").tag("")
                        ForEach(AnimalGroup.allCases) { g in
                            Section(g.label) {
                                ForEach(Species.all.filter { $0.group == g }) { s in
                                    Text(s.commonName).tag(s.classId)
                                }
                            }
                        }
                        Text("Something else, not on this list").tag("unknown")
                    }
                } footer: {
                    Text("Your answer replaces the model’s label on this post.")
                }
                Section {
                    Toggle("Send to the project team for review", isOn: $share)
                } footer: {
                    Text("It helps them find mistakes; it doesn’t change the model on its own.")
                }
                if sendFailed {
                    Text("The review service isn’t reachable, so the correction was only saved on this post.")
                        .foregroundStyle(Color.redwood)
                }
            }
            .navigationTitle("What is it?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(choice.isEmpty)
                }
            }
            .onAppear { choice = initial ?? "" }
        }
    }

    private func save() async {
        if share {
            let ok = await WildlifeAPI.current.sendFeedback(predicted: current, corrected: choice)
            if !ok {
                sendFailed = true
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        if choice != "unknown" { onPick(choice) }
        dismiss()
    }
}

// MARK: - Camera & scan line

private struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

/// One line sweeping the photo while the detector runs.
private struct ScanLine: View {
    @State private var down = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            if !reduceMotion {
                Rectangle()
                    .fill(Color.slug)
                    .frame(height: 2)
                    .shadow(color: .slug.opacity(0.8), radius: 6)
                    .offset(y: down ? geo.size.height - 2 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { down = true }
                    }
            }
        }
    }
}

#Preview {
    IdentifyView().environment(SightingStore())
}
