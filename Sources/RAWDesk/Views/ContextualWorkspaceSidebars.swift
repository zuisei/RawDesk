import SwiftUI

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
