import SwiftUI

struct GPXTracklogView: View {
    @ObservedObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    private var tracklog: GPXTracklog? {
        library.loadedGPXTracklog
    }

    private var preview: GPXAutoTagPreview? {
        library.gpxAutoTagPreview
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let tracklog {
                Form {
                    Section("Tracklog") {
                        LabeledContent(
                            "File",
                            value: tracklog.name
                        )
                        LabeledContent(
                            "Track points",
                            value: "\(tracklog.points.count)"
                        )
                        LabeledContent(
                            "Time range",
                            value: timeRange(tracklog)
                        )
                        Toggle(
                            "Show track on map",
                            isOn: $library.isGPXTrackVisible
                        )
                    }

                    Section("Match Photos") {
                        Picker(
                            "Photos",
                            selection:
                                $library.gpxMatchSettings
                                    .photoScope
                        ) {
                            ForEach(GPXPhotoScope.allCases) {
                                scope in
                                Text(scope.name).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("Tracklog time offset")
                            Spacer()
                            Stepper(
                                value: offsetMinutes,
                                in: -1_440...1_440,
                                step: 1
                            ) {
                                Text(offsetText)
                                    .monospacedDigit()
                                    .frame(
                                        width: 76,
                                        alignment: .trailing
                                    )
                            }
                        }

                        Picker(
                            "Maximum point gap",
                            selection:
                                $library.gpxMatchSettings
                                    .maximumPointGap
                        ) {
                            Text("1 minute")
                                .tag(TimeInterval(60))
                            Text("5 minutes")
                                .tag(TimeInterval(300))
                            Text("15 minutes")
                                .tag(TimeInterval(900))
                            Text("1 hour")
                                .tag(TimeInterval(3_600))
                        }

                        Toggle(
                            "Replace existing photo locations",
                            isOn:
                                $library.gpxMatchSettings
                                    .overwriteExistingLocations
                        )
                    }

                    Section("Preview") {
                        if let preview {
                            previewRow(
                                "Will be tagged",
                                count: preview.matchedCount,
                                tint:
                                    RAWDeskTokens.ColorToken
                                        .success
                            )
                            previewRow(
                                "Already tagged",
                                count:
                                    preview.skippedExistingCount,
                                tint:
                                    RAWDeskTokens.ColorToken
                                        .textSecondary
                            )
                            previewRow(
                                "No capture time",
                                count:
                                    preview.missingCaptureDateCount,
                                tint:
                                    RAWDeskTokens.ColorToken
                                        .warning
                            )
                            previewRow(
                                "Outside track",
                                count: preview.outsideTrackCount,
                                tint:
                                    RAWDeskTokens.ColorToken
                                        .textSecondary
                            )
                        } else {
                            Text("No preview is available.")
                                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        }
                    }

                    Section {
                        Text(
                            "The offset is added to GPX timestamps before they are compared with camera capture times. Coordinates between nearby track points are interpolated."
                        )
                        .font(RAWDeskTokens.Typography.metadata)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                    }
                }
                .formStyle(.grouped)
                .rawPanelScrollBackground()
            } else {
                VStack(spacing: RAWDeskTokens.Spacing.small) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(RAWDeskTokens.Typography.modalTitle)
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    Text("No GPX tracklog is loaded.")
                    Button("Load Tracklog…") {
                        library.loadGPXTracklogPicker()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 650)
    }

    private var header: some View {
        HStack(spacing: RAWDeskTokens.Spacing.small) {
            Image(
                systemName:
                    "point.topleft.down.to.point.bottomright.curvepath"
            )
            .font(RAWDeskTokens.Typography.modalTitle)
            .foregroundStyle(RAWDeskTokens.ColorToken.selection)
            VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                Text("GPS Tracklog")
                    .font(RAWDeskTokens.Typography.workspaceHeader)
                Text(
                    "Match capture times to a timestamped GPX route."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
            Spacer()
        }
        .padding(RAWDeskTokens.Spacing.large)
    }

    private var footer: some View {
        HStack {
            if tracklog != nil {
                Button("Clear Tracklog") {
                    library.clearGPXTracklog()
                }
                Button("Load Another…") {
                    library.loadGPXTracklogPicker()
                }
            }
            Spacer()
            Button("Close") {
                library.isGPXTracklogPresented = false
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            if tracklog != nil {
                Button {
                    let count = library.applyGPXAutoTag()
                    if count > 0 {
                        library.isGPXTracklogPresented = false
                        dismiss()
                    }
                } label: {
                    Text(
                        "Auto-Tag \(preview?.matchedCount ?? 0) Photo\(preview?.matchedCount == 1 ? "" : "s")"
                    )
                }
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
                .disabled(preview?.matchedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(RAWDeskTokens.Spacing.medium)
    }

    private var offsetMinutes: Binding<Int> {
        Binding(
            get: {
                Int(
                    (
                        library.gpxMatchSettings
                            .tracklogOffset / 60
                    ).rounded()
                )
            },
            set: { value in
                library.gpxMatchSettings.tracklogOffset =
                    TimeInterval(value * 60)
            }
        )
    }

    private var offsetText: String {
        let minutes = offsetMinutes.wrappedValue
        let sign = minutes < 0 ? "−" : "+"
        let absolute = abs(minutes)
        return String(
            format: "%@%02d:%02d",
            sign,
            absolute / 60,
            absolute % 60
        )
    }

    private func previewRow(
        _ label: String,
        count: Int,
        tint: Color
    ) -> some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(label)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
        }
    }

    private func timeRange(
        _ tracklog: GPXTracklog
    ) -> String {
        guard let start = tracklog.startDate,
              let end = tracklog.endDate else {
            return "—"
        }
        return "\(Self.dateFormatter.string(from: start)) – \(Self.dateFormatter.string(from: end))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
