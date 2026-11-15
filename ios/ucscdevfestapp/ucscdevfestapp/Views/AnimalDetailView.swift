//
//  AnimalDetailView.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI

/// Detail view for a single animal post.
/// Figma: "back to homepage" button, name (species) header,
/// large photo, map showing sighting location, comments/ratings bar.
struct AnimalDetailView: View {
    @Environment(SightingStore.self) private var store
    let animalID: String

    @AppStorage("displayName") private var displayName = ""
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var commentFocused: Bool

    var body: some View {
        if let animal = store.animal(id: animalID) {
            content(animal)
        } else {
            ContentUnavailableView("Sighting not found", systemImage: "questionmark.circle")
        }
    }

    private func content(_ animal: Animal) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Photo section
                RemotePhoto(url: animal.imageURL, symbolSize: 64)
                    .frame(height: 350)

                // Map section
                if let latitude = animal.latitude, let longitude = animal.longitude {
                    SightingMapView(title: animal.name, latitude: latitude, longitude: longitude)
                        .frame(height: 260)
                } else {
                    Label("No location was shared for this sighting", systemImage: "mappin.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                }

                // Comments / Ratings bar
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Label(animal.ratingText, systemImage: "star.fill")
                            .foregroundStyle(.orange)
                        Label(animal.commentCount == 1 ? "1 comment" : "\(animal.commentCount) comments",
                              systemImage: "bubble.right")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)

                    if animal.isDemo == true {
                        Text("DEMO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(animal.scientificName).italic()
                        Text(animal.lowConfidence
                             ? "\(animal.confidenceText). The model was not sure about this one."
                             : animal.confidenceText)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    if !animal.description.isEmpty {
                        Text(animal.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack {
                        Text("Your rating")
                            .font(.subheadline)
                        Spacer()
                        StarPicker(rating: animal.myRating ?? 0) { stars in
                            Task { await rate(animal, stars: stars) }
                        }
                    }

                    Divider()

                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.author)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(comment.text)
                                .font(.subheadline)
                        }
                    }

                    HStack {
                        TextField("Add a comment", text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("commentField")
                            .focused($commentFocused)
                        Button("Post") {
                            Task { await postComment(animal) }
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground))
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("\(animal.name) (\(animal.species))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { commentFocused = false }
            }
        }
        .task(id: animal.id) { await loadComments(animal) }
    }

    private func loadComments(_ animal: Animal) async {
        do {
            comments = try await APIClient.shared.comments(for: animal)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rate(_ animal: Animal, stars: Int) async {
        do {
            store.upsert(try await APIClient.shared.rate(animal, stars: stars))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func postComment(_ animal: Animal) async {
        isSending = true
        defer { isSending = false }
        do {
            let author = displayName.trimmingCharacters(in: .whitespaces)
            let comment = try await APIClient.shared.addComment(
                to: animal, author: author.isEmpty ? "Anonymous" : author, text: draft
            )
            comments.append(comment)
            draft = ""
            commentFocused = false
            errorMessage = nil
            var updated = animal
            updated.commentCount += 1
            store.upsert(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Five tappable stars.
struct StarPicker: View {
    let rating: Int
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onPick(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
    }
}
