//
//  RemotePhoto.swift
//  ucscdevfestapp
//
//  Photo area used by every card: loads from the API, shows the Figma placeholder meanwhile.
//

import SwiftUI

struct RemotePhoto: View {
    let url: URL?
    var placeholderSymbol = "photo"
    var symbolSize: CGFloat = 48

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty where url != nil:
                        ProgressView()
                    default:
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: symbolSize))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                // scaledToFill overflows the frame. It is clipped visually, and this
                // keeps the overflow from swallowing taps meant for neighbouring cards.
                .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// Shown in place of a list when there is nothing to show or the server is unreachable.
struct FeedStatusView: View {
    @Environment(SightingStore.self) private var store
    var emptyTitle = "No sightings yet"
    var emptyMessage = "Tap the camera button to post the first one."

    var body: some View {
        if let message = store.errorMessage {
            ContentUnavailableView {
                Label("Can't load sightings", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.refresh() } }
            }
        } else if !store.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ContentUnavailableView(emptyTitle, systemImage: "camera.viewfinder", description: Text(emptyMessage))
        }
    }
}
