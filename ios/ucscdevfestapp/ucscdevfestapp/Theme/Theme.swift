//
//  Theme.swift
//  ucscdevfestapp
//
//  Shared tokens with the web app (web/src/index.css in the model repo):
//  canopy green ink, redwood for actions, banana-slug yellow = "the model named it",
//  and one colour per animal group, always shown next to a text label.
//  Surfaces use system backgrounds so Dark Mode keeps working.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let canopy = Color(hex: 0x1E3B2F)
    static let redwood = Color(hex: 0x6B2E1F)
    static let slug = Color(hex: 0xF2C230)
    static let lichen = Color(hex: 0xA9B8A3)

    static func group(_ g: AnimalGroup) -> Color {
        switch g {
        case .largeMammal: return Color(hex: 0x9A4A35) // redwood, lifted so it reads in Dark Mode too
        case .smallMammal: return Color(hex: 0xB58A1C)
        case .bird: return Color(hex: 0x3B7096)
        case .gastropod: return Color(hex: 0xA48513)
        case .tree: return Color(hex: 0x3D7A53)
        case .insect: return Color(hex: 0x946435)
        case .arthropod: return Color(hex: 0x806284)
        }
    }

    /// Bracket and tag colour for each model outcome.
    static func status(_ s: PredictionStatus) -> Color {
        switch s {
        case .identified: return .slug
        case .uncertain: return .white
        case .unsupported, .noAnimal: return .lichen
        }
    }
}

/// One type scale for the whole app: condensed heavy SF for headings and numbers,
/// regular SF for everything else. All sizes scale with Dynamic Type.
extension Font {
    static let wDisplay = Font.system(.largeTitle, weight: .heavy).width(.condensed)
    static let wTitle = Font.system(.title, weight: .heavy).width(.condensed)
    static let wHeading = Font.system(.title3, weight: .heavy).width(.condensed)
    static let wNumber = Font.system(.title, weight: .heavy).width(.condensed).monospacedDigit()
}

// MARK: - Corner brackets (the detector box)

/// Field-guide corner brackets instead of a full rectangle.
struct BracketShape: Shape {
    var fraction: CGFloat = 0.22

    func path(in r: CGRect) -> Path {
        let l = min(r.width, r.height) * fraction
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

// MARK: - Small shared pieces

struct GroupChip: View {
    let group: AnimalGroup?

    var body: some View {
        if let group {
            HStack(spacing: 6) {
                Circle().fill(Color.group(group)).frame(width: 8, height: 8)
                Text(group.label)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.group(group).opacity(0.16), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }
}

/// The model's photo rating (0–100), or nothing when the animal wasn't identified.
struct RatingView: View {
    let rating: Int?
    var large = false

    var body: some View {
        if let rating {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(rating)").font(large ? .wDisplay.monospacedDigit() : .wNumber)
                Text("photo rating").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo rating \(rating) out of 100")
        }
    }
}

/// Where a photo comes from.
enum PhotoSource: Equatable {
    case remote(URL)
    case file(URL)
    case image(UIImage)
}

/// Loads any `PhotoSource`, filling its frame.
struct PhotoImage: View {
    let source: PhotoSource?

    var body: some View {
        switch source {
        case .remote(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else if phase.error != nil {
                    placeholder(systemImage: "wifi.slash")
                } else {
                    placeholder(systemImage: nil)
                }
            }
        case .file(let url):
            if let ui = UIImage(contentsOfFile: url.path) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                placeholder(systemImage: "photo")
            }
        case .image(let ui):
            Image(uiImage: ui).resizable().scaledToFill()
        case nil:
            placeholder(systemImage: "photo")
        }
    }

    private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Color.canopy.opacity(0.85)
            if let systemImage {
                Image(systemName: systemImage).font(.title).foregroundStyle(.white.opacity(0.6))
            } else {
                ProgressView().tint(.white)
            }
        }
    }
}

extension SightingStore {
    func photoSource(_ s: Sighting) -> PhotoSource? {
        if let filename = s.bundledImageFile, let url = Bundle.main.url(forResource: filename, withExtension: nil) { return .file(url) }
        if let url = s.imageURL { return .remote(url) }
        if let url = localImageURL(s) { return .file(url) }
        return nil
    }
}
