import SwiftUI
import AppKit

extension PhotoColorLabel {
    var swatchColor: Color {
        switch self {
        case .none:
            return RAWDeskTokens.ColorToken
                .textSecondary
        case .red:
            return Color(nsColor: .systemRed)
        case .yellow:
            return Color(nsColor: .systemYellow)
        case .green:
            return Color(nsColor: .systemGreen)
        case .blue:
            return Color(nsColor: .systemBlue)
        case .purple:
            return Color(nsColor: .systemPurple)
        }
    }

    var menuSymbol: String {
        self == .none ? "circle.slash" : "circle.fill"
    }
}

struct PhotoColorLabelMenuItems: View {
    let current: PhotoColorLabel?
    var labelSet: PhotoColorLabelSet = .standard
    var editAction: (() -> Void)?
    let action: (PhotoColorLabel) -> Void

    var body: some View {
        ForEach(PhotoColorLabel.allCases) { label in
            Button {
                action(label)
            } label: {
                Label(
                    label == .none ? "None" : labelSet[label],
                    systemImage: current == label
                        ? "checkmark.circle.fill"
                        : label.menuSymbol
                )
            }
        }
        if let editAction {
            Divider()
            Button("Edit Color Label Sets…", action: editAction)
        }
    }
}

struct ColorLabelSwatch: View {
    let label: PhotoColorLabel
    var isSelected = false
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    label == .none
                        ? Color.clear
                        : label.swatchColor
                )
            Circle()
                .stroke(
                    label == .none
                        ? label.swatchColor
                        : RAWDeskTokens.ColorToken.textPrimary.opacity(0.18),
                    lineWidth: label == .none ? 1.5 : 1
                )
            if label == .none {
                Rectangle()
                    .fill(label.swatchColor)
                    .frame(width: size * 0.9, height: 1.4)
                    .rotationEffect(.degrees(-45))
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.58, weight: .bold))
                    .foregroundStyle(
                        label == .yellow || label == .none
                            ? Color.black.opacity(0.75)
                            : RAWDeskTokens.ColorToken
                                .textPrimary
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct ColorLabelFilterButton: View {
    let label: PhotoColorLabel
    let displayName: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: RAWDeskTokens.Spacing.xSmall) {
                ColorLabelSwatch(
                    label: label,
                    isSelected: isSelected,
                    size: 18
                )
                Text("\(count)")
                    .font(RAWDeskTokens.Typography.badge)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, RAWDeskTokens.Spacing.xSmall)
            .background(
                isSelected
                    ? RAWDeskTokens.ColorToken.selection.opacity(0.13)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: RAWDeskTokens.Radius.control)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            isSelected
                ? "Stop filtering by \(displayName)"
                : "Include \(displayName) photos"
        )
        .accessibilityLabel(Text("\(displayName), \(count) photos"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
