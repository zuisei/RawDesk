import SwiftUI

struct HistogramView: View {
    let data: HistogramData

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                .fill(RAWDeskTokens.ColorToken.canvas)

            histogramGrid

            if data.red.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .tint(
                        RAWDeskTokens.ColorToken
                            .textPrimary.opacity(0.7)
                    )
            } else {
                HistogramShape(values: data.red)
                    .fill(Color.red.opacity(0.48))
                    .blendMode(.screen)
                HistogramShape(values: data.green)
                    .fill(Color.green.opacity(0.48))
                    .blendMode(.screen)
                HistogramShape(values: data.blue)
                    .fill(Color.blue.opacity(0.48))
                    .blendMode(.screen)
            }

            VStack {
                HStack {
                    clippingIndicator(
                        color: .blue,
                        fraction: data.shadowClippingFraction,
                        label: "Shadow clipping"
                    )
                    Spacer()
                    clippingIndicator(
                        color: .red,
                        fraction: data.highlightClippingFraction,
                        label: "Highlight clipping"
                    )
                }
                Spacer()
            }
            .padding(RAWDeskTokens.Spacing.xSmall)
        }
        .clipShape(RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
                .stroke(RAWDeskTokens.ColorToken.divider)
        )
    }

    private func clippingIndicator(
        color: Color,
        fraction: CGFloat,
        label: String
    ) -> some View {
        Image(systemName: "triangle.fill")
            .font(.system(size: 8))
            .foregroundStyle(
                fraction > 0.0005
                    ? color
                    : RAWDeskTokens.ColorToken
                        .textSecondary.opacity(0.4)
            )
            .help("\(label): \(String(format: "%.2f", fraction * 100))%")
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text("\(fraction * 100, specifier: "%.2f") percent"))
    }

    private var histogramGrid: some View {
        GeometryReader { geometry in
            Path { path in
                for fraction in [0.25, 0.5, 0.75] {
                    let x = geometry.size.width * fraction
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
                let midY = geometry.size.height * 0.5
                path.move(to: CGPoint(x: 0, y: midY))
                path.addLine(to: CGPoint(x: geometry.size.width, y: midY))
            }
            .stroke(
                RAWDeskTokens.ColorToken.divider,
                lineWidth: 0.5
            )
        }
    }
}

private struct HistogramShape: Shape {
    let values: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let denominator = CGFloat(max(1, values.count - 1))
        for (index, value) in values.enumerated() {
            let x = rect.minX + CGFloat(index) / denominator * rect.width
            let y = rect.maxY - max(0, min(1, value)) * rect.height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
