import SwiftUI

struct CaptureTimeAutoStackView: View {
    @ObservedObject var library: LibraryViewModel

    @State private var maximumGap: TimeInterval = 10

    private var preview: CaptureTimeAutoStackPreview {
        library.captureTimeAutoStackPreview(
            maximumGap: maximumGap
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.large) {
            header
            intervalControl
            previewCard
            Divider()
            actions
        }
        .padding(RAWDeskTokens.Spacing.xLarge)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(
            "Auto Stack by Capture Time dialog"
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: RAWDeskTokens.Spacing.medium) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.selection
                )
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("Auto Stack by Capture Time")
                    .font(RAWDeskTokens.Typography.modalTitle)
                Text(
                    "Uses every unstacked photo in “\(library.displayTitle)”, not only the current selection. Photos are never grouped across folders."
                )
                .font(RAWDeskTokens.Typography.control)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var intervalControl: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.small) {
            Stepper(
                value: rawClampedBinding(
                    $maximumGap,
                    in:
                        0...CaptureTimeAutoStackPlanner
                            .maximumSupportedGap
                ),
                in: 0...CaptureTimeAutoStackPlanner
                    .maximumSupportedGap,
                step: 1
            ) {
                HStack {
                    Text("Maximum gap between consecutive photos")
                    Spacer()
                    TextField(
                        "Maximum gap in seconds",
                        value: rawClampedBinding(
                            $maximumGap,
                            in:
                                0...CaptureTimeAutoStackPlanner
                                    .maximumSupportedGap
                        ),
                        format: .number.precision(
                            .fractionLength(0)
                        )
                    )
                    .rawNumericField(width: 66)
                    Text("sec")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
            }
            .accessibilityIdentifier(
                "Capture time maximum gap stepper"
            )

            Slider(
                value: logarithmicSliderBinding,
                in: 0...1
            )
            .rawKeyboardAdjustableSlider(
                value: logarithmicSliderBinding,
                in: 0...1,
                step: 0.01
            )
            .rawSliderTarget()
            .accessibilityLabel(
                "Maximum gap between consecutive photos"
            )
            .accessibilityValue(Self.durationLabel(maximumGap))
            .accessibilityIdentifier(
                "Capture time maximum gap slider"
            )

            HStack {
                Text("0 seconds")
                Spacer()
                Text("1 hour")
            }
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)

            Text(
                "A photo joins the current stack when it was captured within this interval of the previous photo."
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
    }

    private var previewCard: some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.medium
        ) {
            Text("Preview")
                .font(
                    RAWDeskTokens.Typography
                        .workspaceHeader
                )
            Divider()
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.medium) {
                if preview.stackCount == 0 {
                    Label {
                        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                            Text("No stacks at this interval")
                                .font(RAWDeskTokens.Typography.workspaceHeader)
                            Text(
                                "Increase the gap to include more consecutive photos."
                            )
                            .font(RAWDeskTokens.Typography.control)
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "photo.stack")
                            .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    }
                } else {
                    HStack(spacing: RAWDeskTokens.Spacing.xLarge) {
                        PreviewMetric(
                            value: "\(preview.stackCount)",
                            label: preview.stackCount == 1
                                ? "Stack"
                                : "Stacks"
                        )
                        PreviewMetric(
                            value: "\(preview.groupedPhotoCount)",
                            label: "Photos grouped"
                        )
                        PreviewMetric(
                            value:
                                "\(preview.ungroupedEligiblePhotoCount)",
                            label: "Left separate"
                        )
                    }
                    Text(groupSizeSummary)
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }

                Divider()

                if preview.alreadyStackedPhotoCount > 0 {
                    exclusionLabel(
                        count: preview.alreadyStackedPhotoCount,
                        singular: "photo already in a stack is unchanged",
                        plural:
                            "photos already in stacks are unchanged",
                        systemImage: "rectangle.stack"
                    )
                }
                if preview.missingCaptureTimePhotoCount > 0 {
                    exclusionLabel(
                        count: preview.missingCaptureTimePhotoCount,
                        singular:
                            "photo without a capture time is excluded",
                        plural:
                            "photos without capture times are excluded",
                        systemImage: "clock.badge.questionmark"
                    )
                }
                if preview.unavailablePhotoCount > 0 {
                    exclusionLabel(
                        count: preview.unavailablePhotoCount,
                        singular: "missing photo is excluded",
                        plural: "missing photos are excluded",
                        systemImage: "questionmark.folder"
                    )
                }

                Label(
                    "Only catalog organization changes. Original image files and XMP sidecars are not moved or rewritten.",
                    systemImage: "lock.shield"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(RAWDeskTokens.Spacing.medium)
        .background(
            RAWDeskTokens.ColorToken.panel,
            in: RoundedRectangle(
                cornerRadius: RAWDeskTokens.Radius.group
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Auto stack preview")
    }

    private var actions: some View {
        HStack {
            Button("Cancel") {
                library.isCaptureTimeAutoStackPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier(
                "Cancel capture time auto stack"
            )

            Spacer()

            Button(createButtonTitle) {
                _ = library.createCaptureTimePhotoStacks(
                    maximumGap: maximumGap
                )
            }
            .keyboardShortcut(.defaultAction)
            .disabled(preview.stackCount == 0)
            .accessibilityIdentifier(
                "Create capture time stacks"
            )
            .help(
                "Create the previewed stacks without changing original files"
            )
        }
    }

    private var logarithmicSliderBinding: Binding<Double> {
        Binding(
            get: {
                guard maximumGap > 0 else { return 0 }
                return log1p(maximumGap)
                    / log1p(
                        CaptureTimeAutoStackPlanner
                            .maximumSupportedGap
                    )
            },
            set: { sliderValue in
                let maximum = CaptureTimeAutoStackPlanner
                    .maximumSupportedGap
                let raw = exp(sliderValue * log1p(maximum)) - 1
                maximumGap = Self.roundedSliderGap(raw)
            }
        )
    }

    private var createButtonTitle: String {
        if preview.stackCount == 1 {
            return "Create 1 Stack"
        }
        return "Create \(preview.stackCount) Stacks"
    }

    private var groupSizeSummary: String {
        let counts = Dictionary(
            grouping: preview.groups,
            by: \.photoCount
        ).mapValues(\.count)
        return counts.keys.sorted().map { size in
            let count = counts[size] ?? 0
            return count == 1
                ? "1 stack of \(size) photos"
                : "\(count) stacks of \(size) photos"
        }.joined(separator: " · ")
    }

    private func exclusionLabel(
        count: Int,
        singular: String,
        plural: String,
        systemImage: String
    ) -> some View {
        Label(
            "\(count) \(count == 1 ? singular : plural)",
            systemImage: systemImage
        )
        .font(RAWDeskTokens.Typography.metadata)
        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
    }

    private static func roundedSliderGap(
        _ value: TimeInterval
    ) -> TimeInterval {
        let clamped = CaptureTimeAutoStackPlanner.normalizedGap(value)
        let step: TimeInterval
        switch clamped {
        case ..<60:
            step = 1
        case ..<300:
            step = 5
        case ..<900:
            step = 15
        default:
            step = 60
        }
        return min(
            CaptureTimeAutoStackPlanner.maximumSupportedGap,
            max(0, (clamped / step).rounded() * step)
        )
    }

    static func durationLabel(
        _ rawSeconds: TimeInterval
    ) -> String {
        let totalSeconds = Int(
            CaptureTimeAutoStackPlanner.normalizedGap(rawSeconds)
                .rounded()
        )
        if totalSeconds == 0 {
            return "0 seconds"
        }
        if totalSeconds == 3_600 {
            return "1 hour"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 {
            return totalSeconds == 1
                ? "1 second"
                : "\(totalSeconds) seconds"
        }
        let minutePart = minutes == 1
            ? "1 minute"
            : "\(minutes) minutes"
        guard seconds > 0 else { return minutePart }
        let secondPart = seconds == 1
            ? "1 second"
            : "\(seconds) seconds"
        return "\(minutePart) \(secondPart)"
    }
}

private struct PreviewMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
            Text(value)
                .font(RAWDeskTokens.Typography.modalTitle)
                .monospacedDigit()
            Text(label)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
