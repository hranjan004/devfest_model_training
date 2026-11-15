//
//  ResultViews.swift
//  ucscdevfestapp
//
//  How sure the model is (top 3) and the photo-quality breakdown.
//

import SwiftUI

struct TopThreeView: View {
    let detection: Detection
    var animate = false
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(detection.top3.enumerated()), id: \.offset) { i, c in
                let pct = String(format: "%.1f%%", c.probability * 100)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.species?.commonName ?? c.classId)
                            .fontWeight(i == 0 ? .bold : .regular)
                            .foregroundStyle(i == 0 ? .primary : .secondary)
                        Spacer()
                        Text(pct).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Bar(value: shown ? c.probability : 0, color: c.species.map { Color.group($0.group) } ?? .lichen)
                        .opacity(i == 0 ? 1 : 0.6)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            guard animate else { shown = true; return }
            withAnimation(.easeOut(duration: 0.7).delay(0.6)) { shown = true }
        }
    }
}

struct QualityView: View {
    let quality: PhotoQuality

    private var rows: [(String, Int)] {
        [("Sharpness", quality.sharpness), ("Visibility estimate", quality.visibility), ("Exposure", quality.exposure),
         ("Resolution", quality.resolution), ("Composition", quality.composition)]
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { name, value in
                GridRow {
                    Text(name).foregroundStyle(.secondary)
                    Bar(value: Double(value) / 100, color: .secondary, height: 6)
                    Text("\(value)").monospacedDigit().frame(minWidth: 28, alignment: .trailing)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct Bar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemFill))
                Capsule().fill(color).frame(width: max(geo.size.width * min(max(value, 0), 1), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Section heading used on detail and result screens.
struct SectionHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.wHeading).accessibilityAddTraits(.isHeader)
    }
}
