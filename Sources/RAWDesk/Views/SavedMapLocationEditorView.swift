import SwiftUI

struct SavedMapLocationEditorView: View {
    @ObservedObject var library: LibraryViewModel
    let initial: SavedMapLocation

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var folder: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var radius: String
    @State private var radiusUnit: SavedLocationRadiusUnit
    @State private var isPrivate: Bool
    @State private var isVisible: Bool
    @State private var validationMessage: String?
    @State private var confirmsDeletion = false

    init(
        library: LibraryViewModel,
        initial: SavedMapLocation
    ) {
        self.library = library
        self.initial = initial
        let unit: SavedLocationRadiusUnit =
            initial.radiusMeters >= 1_000
                ? .kilometers
                : .meters
        _name = State(initialValue: initial.name)
        _folder = State(initialValue: initial.folder)
        _latitude = State(
            initialValue: Self.decimal(
                initial.center.latitude,
                digits: 6
            )
        )
        _longitude = State(
            initialValue: Self.decimal(
                initial.center.longitude,
                digits: 6
            )
        )
        _radius = State(
            initialValue: Self.decimal(
                initial.radiusMeters / unit.meters,
                digits:
                    initial.radiusMeters >= 1_000 ? 2 : 0
            )
        )
        _radiusUnit = State(initialValue: unit)
        _isPrivate = State(initialValue: initial.isPrivate)
        _isVisible = State(initialValue: initial.isVisible)
    }

    private var isExisting: Bool {
        library.savedMapLocations.contains {
            $0.id == initial.id
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Image(
                    systemName:
                        isPrivate
                        ? "lock.circle.fill"
                        : "mappin.circle.fill"
                )
                .font(RAWDeskTokens.Typography.modalTitle)
                .foregroundStyle(
                    isPrivate
                        ? RAWDeskTokens.ColorToken.warning
                        : RAWDeskTokens.ColorToken.selection
                )
                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(
                        isExisting
                            ? "Edit Saved Location"
                            : "New Saved Location"
                    )
                    .font(RAWDeskTokens.Typography.workspaceHeader)
                    Text(
                        "A reusable area for map navigation and export privacy."
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }
                Spacer()
            }
            .padding(RAWDeskTokens.Spacing.large)

            Divider()

            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Folder", text: $folder)
                    Toggle("Show on map", isOn: $isVisible)
                }

                Section("Center") {
                    HStack {
                        TextField("Latitude", text: $latitude)
                            .rawNumericField()
                        TextField("Longitude", text: $longitude)
                            .rawNumericField()
                    }
                    Text(
                        "Latitude −90…90 · Longitude −180…180"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                }

                Section("Radius") {
                    HStack {
                        TextField("Radius", text: $radius)
                            .rawNumericField()
                        Picker("Unit", selection: $radiusUnit) {
                            ForEach(
                                SavedLocationRadiusUnit.allCases
                            ) { unit in
                                Text(unit.name).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }
                }

                Section {
                    Toggle(
                        isOn: $isPrivate
                    ) {
                        Label(
                            "Private location",
                            systemImage:
                                isPrivate
                                ? "lock.fill"
                                : "lock.open"
                        )
                    }
                    Text(
                        "Exports of photos inside this radius omit GPS and IPTC sublocation, city, state, and country fields. Catalog metadata remains intact."
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(RAWDeskTokens.ColorToken.textSecondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                if let validationMessage {
                    Section {
                        Label(
                            validationMessage,
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .foregroundStyle(RAWDeskTokens.ColorToken.warning)
                    }
                }
            }
            .formStyle(.grouped)
            .rawPanelScrollBackground()

            Divider()

            HStack {
                if isExisting {
                    Button(
                        "Delete",
                        role: .destructive
                    ) {
                        confirmsDeletion = true
                    }
                }
                Spacer()
                Button("Cancel") {
                    library.editingSavedMapLocation = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .rawPrimaryButtonHeight()
                .keyboardShortcut(.defaultAction)
            }
            .padding(RAWDeskTokens.Spacing.medium)
        }
        .frame(width: 520, height: 620)
        .confirmationDialog(
            "Delete “\(initial.name)”?",
            isPresented: $confirmsDeletion
        ) {
            Button(
                "Delete Saved Location",
                role: .destructive
            ) {
                library.deleteSavedMapLocation(initial.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Photos and their location metadata are not changed."
            )
        }
    }

    private func save() {
        guard let latitudeValue = Self.number(latitude),
              let longitudeValue = Self.number(longitude),
              let center = PhotoLocation(
                  latitude: latitudeValue,
                  longitude: longitudeValue
              ) else {
            validationMessage =
                "Enter valid latitude and longitude values."
            return
        }
        guard let radiusValue = Self.number(radius),
              radiusValue.isFinite,
              radiusValue > 0 else {
            validationMessage = "Enter a positive radius."
            return
        }
        let radiusMeters = radiusValue * radiusUnit.meters
        guard (10...2_000_000).contains(radiusMeters) else {
            validationMessage =
                "Radius must be between 10 m and 2,000 km."
            return
        }
        let updated = SavedMapLocation(
            id: initial.id,
            name: name,
            folder: folder,
            center: center,
            radiusMeters: radiusMeters,
            isPrivate: isPrivate,
            isVisible: isVisible
        )
        if let message =
                library.saveSavedMapLocation(updated) {
            validationMessage = message
            return
        }
        dismiss()
    }

    private static func number(_ value: String) -> Double? {
        Double(
            value
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .replacingOccurrences(of: ",", with: ".")
        )
    }

    private static func decimal(
        _ value: Double,
        digits: Int
    ) -> String {
        String(
            format: "%.\(digits)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

private enum SavedLocationRadiusUnit:
    String,
    CaseIterable,
    Identifiable
{
    case meters
    case kilometers
    case miles

    var id: String { rawValue }

    var name: String {
        switch self {
        case .meters: return "metres"
        case .kilometers: return "kilometres"
        case .miles: return "miles"
        }
    }

    var meters: Double {
        switch self {
        case .meters: return 1
        case .kilometers: return 1_000
        case .miles: return 1_609.344
        }
    }
}
