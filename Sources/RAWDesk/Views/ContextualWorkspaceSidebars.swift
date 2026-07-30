import SwiftUI

struct PeopleSidebarView: View {
    @ObservedObject var people: PeopleViewModel

    var body: some View {
        List {
            Section("People") {
                categoryRow(
                    title: "Named People",
                    systemImage: "person.text.rectangle",
                    count: people.snapshot.namedGroups.count
                ) {
                    if let group =
                        people.snapshot.namedGroups.first {
                        people.selectGroup(group)
                    }
                }

                categoryRow(
                    title: "Suggested Matches",
                    systemImage: "sparkles.rectangle.stack",
                    count:
                        people.snapshot.suggestedGroups.count
                ) {
                    if let group =
                        people.snapshot.suggestedGroups.first {
                        people.selectGroup(group)
                    }
                }

                categoryRow(
                    title: "Needs Review",
                    systemImage: "person.crop.square",
                    count: people.snapshot.singleFaces.count
                ) {
                    if let face =
                        people.snapshot.singleFaces.first {
                        people.selectFace(face)
                    }
                }

                HStack {
                    Label(
                        "Ignored / Not a Face",
                        systemImage: "eye.slash"
                    )
                    Spacer()
                    if people.snapshot.ignoredFaceCount > 0 {
                        Text(
                            "\(people.snapshot.ignoredFaceCount)"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .monospacedDigit()
                    }
                }

                if people.snapshot.ignoredFaceCount > 0 {
                    Button("Restore Ignored Faces…") {
                        people.restoreIgnoredFaces()
                    }
                    .font(
                        RAWDeskTokens.Typography.metadata
                    )
                }
            }

            Section("Background Analysis") {
                if let progress = people.scanProgress {
                    VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                        ProgressView(
                            value: progress.fractionCompleted
                        )
                        Text(
                            "\(progress.completed) of \(progress.total) photos · \(progress.faceCount) faces"
                        )
                        .font(
                            RAWDeskTokens.Typography.metadata
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .monospacedDigit()
                    }
                } else {
                    Label(
                        people.automaticAnalysisEnabled
                            ? "Ready for new photos"
                            : "Off",
                        systemImage:
                            people.automaticAnalysisEnabled
                            ? "checkmark.circle"
                            : "pause.circle"
                    )
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }

                Toggle(
                    "Analyze new photos",
                    isOn: Binding(
                        get: {
                            people.automaticAnalysisEnabled
                        },
                        set: {
                            people
                                .setAutomaticAnalysisEnabled(
                                    $0
                                )
                        }
                    )
                )

                if people.isScanning {
                    Button(
                        people.isAutomaticScan
                            ? "Pause Analysis"
                            : "Cancel Analysis"
                    ) {
                        if people.isAutomaticScan {
                            people
                                .setAutomaticAnalysisEnabled(
                                    false
                                )
                        } else {
                            people.cancelScan()
                        }
                    }
                } else {
                    Button("Analyze Again") {
                        people.startScan(
                            forceReanalysis: true
                        )
                    }
                }
            }

            Section {
                RAWStateBadge(
                    text: "Local only",
                    systemImage: "lock.shield",
                    tone: .neutral
                )
                Text(
                    "Suggestions require your confirmation and are not identity verification."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
            }
        }
        .listStyle(.sidebar)
        .rawPanelScrollBackground()
    }

    private func categoryRow(
        title: String,
        systemImage: String,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct MapSidebarView: View {
    @ObservedObject var library: LibraryViewModel

    @AppStorage("rawdesk.map.photoScope")
    private var photoScopeRaw =
        MapPhotoScope.all.rawValue
    @AppStorage("rawdesk.map.displayStyle")
    private var mapStyleRaw =
        MapDisplayStyle.standard.rawValue

    private var availableAssets: [PhotoAsset] {
        library.filtered.filter {
            !$0.catalogMissing
        }
    }

    private var locatedCount: Int {
        availableAssets.lazy.filter {
            $0.effectiveLocation != nil
        }.count
    }

    var body: some View {
        List {
            Section("Photos") {
                scopeRow(
                    .tagged,
                    title: "With Location",
                    count: locatedCount
                )
                scopeRow(
                    .untagged,
                    title: "Without Location",
                    count:
                        availableAssets.count
                        - locatedCount
                )
                scopeRow(
                    .all,
                    title: "All Photos",
                    count: availableAssets.count
                )
            }

            Section("Saved Locations") {
                if library.savedMapLocations.isEmpty {
                    Text("No saved locations")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                } else {
                    ForEach(
                        library.savedMapLocations
                    ) { location in
                        Button {
                            library.focusSavedMapLocation(
                                location.id
                            )
                        } label: {
                            HStack {
                                Label(
                                    location.name,
                                    systemImage:
                                        location.isPrivate
                                        ? "lock.fill"
                                        : "mappin.and.ellipse"
                                )
                                Spacer()
                                if location.isPrivate {
                                    Text("Private")
                                        .font(
                                            RAWDeskTokens
                                                .Typography
                                                .badge
                                        )
                                        .foregroundStyle(
                                            RAWDeskTokens
                                                .ColorToken
                                                .textSecondary
                                        )
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("New Saved Location…") {
                    _ = library
                        .presentNewSavedMapLocation()
                }
            }

            Section("GPX") {
                if let tracklog =
                    library.loadedGPXTracklog {
                    Label(
                        tracklog.name,
                        systemImage:
                            "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    Toggle(
                        "Show Track",
                        isOn:
                            $library.isGPXTrackVisible
                    )
                    Button("Tracklog Settings…") {
                        library.isGPXTracklogPresented = true
                    }
                    Button("Clear Tracklog") {
                        library.clearGPXTracklog()
                    }
                } else {
                    Button("Load GPX Tracklog…") {
                        library.loadGPXTracklogPicker()
                    }
                }
            }

            Section("Map Style") {
                Picker(
                    "Map Style",
                    selection: $mapStyleRaw
                ) {
                    ForEach(
                        MapDisplayStyle.allCases
                    ) { style in
                        Text(style.name)
                            .tag(style.rawValue)
                    }
                }
                .labelsHidden()
            }

            Section {
                Label(
                    "Catalog-only location edits",
                    systemImage: "info.circle"
                )
                .lineLimit(2)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
                Text(
                    "RAWDesk never rewrites the original photo’s EXIF location."
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                .lineLimit(3)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        .listStyle(.sidebar)
        .rawPanelScrollBackground()
    }

    private func scopeRow(
        _ scope: MapPhotoScope,
        title: String,
        count: Int
    ) -> some View {
        Button {
            photoScopeRaw = scope.rawValue
        } label: {
            HStack {
                Label(
                    title,
                    systemImage: scope.systemImage
                )
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            photoScopeRaw == scope.rawValue
                ? RAWDeskTokens.ColorToken.selection
                : RAWDeskTokens.ColorToken.textPrimary
        )
    }
}
