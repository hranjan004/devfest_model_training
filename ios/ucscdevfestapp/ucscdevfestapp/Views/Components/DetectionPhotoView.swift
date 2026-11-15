//
//  DetectionPhotoView.swift
//  ucscdevfestapp
//
//  A photo with the detector's corner brackets and a species tag on each animal.
//  With `animate`, the brackets start at the photo edge and close onto the detector box
//  ("lock-on"), then the tag appears: the app's one orchestrated motion.
//

import SwiftUI

struct DetectionPhotoView: View {
    let source: PhotoSource?
    let width: Double
    let height: Double
    let detections: [Detection]
    var animate = false
    var showTags = true
    var selected: Int? = nil
    var onSelect: ((Int) -> Void)? = nil
    /// Which detection gets a tag when several overlap: the selected one, else the API's primary.
    var primaryIndex: Int? = nil

    @State private var locked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.canopy
            .aspectRatio(width / max(height, 1), contentMode: .fit)
            .overlay { PhotoImage(source: source) }
            .overlay { GeometryReader { geo in boxes(in: geo.size) }.allowsHitTesting(onSelect != nil) }
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityText)
            .onAppear {
                guard animate, !reduceMotion else { locked = true; return }
                locked = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(duration: 0.52, bounce: 0.12)) { locked = true }
                }
            }
    }

    private func boxes(in size: CGSize) -> some View {
        ForEach(Array(detections.enumerated()), id: \.offset) { i, d in
            let r = locked ? rect(for: d, in: size) : size.insetRect(by: 0.02)
            let dimmed = selected != nil && selected != i
            ZStack(alignment: .topLeading) {
                if !d.isWholeImage {
                    BracketShape()
                        .stroke(Color.status(d.status), style: StrokeStyle(lineWidth: 3, lineCap: .square))
                        .shadow(color: .black.opacity(0.55), radius: 1.5)
                }
                if showTags, locked, i == (selected ?? primaryIndex ?? 0) {
                    tag(for: d)
                        .offset(x: tagInside(r) ? 6 : 0, y: tagInside(r) ? 6 : -28)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .frame(width: r.width, height: r.height, alignment: .topLeading)
            .position(x: r.midX, y: r.midY)
            .opacity(dimmed ? 0.4 : 1)
            .contentShape(Rectangle())
            .onTapGesture { onSelect?(i) }
            .accessibilityHidden(onSelect == nil)
            .accessibilityLabel("Animal \(i + 1): \(d.label)")
            .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
        }
    }

    private func tag(for d: Detection) -> some View {
        HStack(spacing: 4) {
            Text(d.label).fontWeight(.bold)
            if d.status == .identified, let c = d.confidenceCalibrated {
                Text(String(format: "%.1f%%", c * 100)).monospacedDigit()
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(Color.canopy)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.status(d.status), in: RoundedRectangle(cornerRadius: 5))
    }

    /// Boxes hugging the top edge get their tag inside so it isn't clipped.
    private func tagInside(_ r: CGRect) -> Bool { r.minY < 30 }

    private func rect(for d: Detection, in size: CGSize) -> CGRect {
        guard d.box.count == 4 else { return size.insetRect(by: 0.02) }
        let sx = size.width / width, sy = size.height / height
        return CGRect(x: d.box[0] * sx, y: d.box[1] * sy, width: (d.box[2] - d.box[0]) * sx, height: (d.box[3] - d.box[1]) * sy)
    }

    private var accessibilityText: String {
        detections.isEmpty ? "Photo with no animal detected" : "Photo of " + detections.map(\.label).joined(separator: ", ")
    }
}

private extension CGSize {
    func insetRect(by fraction: CGFloat) -> CGRect {
        CGRect(x: width * fraction, y: height * fraction, width: width * (1 - 2 * fraction), height: height * (1 - 2 * fraction))
    }
}
