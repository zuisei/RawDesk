import SwiftUI
import AppKit

struct PeopleWorkspaceView: View {
    @ObservedObject var people: PeopleViewModel
    @ObservedObject var library: LibraryViewModel

    private let personColumns = [
        GridItem(
            .adaptive(minimum: 156, maximum: 210),
            spacing: RAWDeskTokens.Spacing.large
        )
    ]
    private let faceColumns = [
        GridItem(
            .adaptive(minimum: 112, maximum: 148),
            spacing: RAWDeskTokens.Spacing.medium
        )
    ]

    private var automaticAnalysisBinding:
        Binding<Bool> {
        Binding(
            get: {
                people.automaticAnalysisEnabled
            },
            set: {
                people.setAutomaticAnalysisEnabled($0)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            Divider()
            Label(
                "Analysis runs only on this Mac. Suggestions are not identity confirmation.",
                systemImage: "lock.shield"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )
            .frame(
                maxWidth: .infinity,
                minHeight: 28,
                alignment: .leading
            )
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.medium
            )
            .accessibilityIdentifier(
                "People local analysis notice"
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .background(RAWDeskTokens.ColorToken.canvas)
        .onAppear {
            people.startIfNeeded()
        }
        .alert(
            "People could not complete the request",
            isPresented: Binding(
                get: { people.errorMessage != nil },
                set: { if !$0 { people.dismissError() } }
            ),
            presenting: people.errorMessage
        ) { _ in
            Button("OK") { people.dismissError() }
        } message: { message in
            Text(message)
        }
    }

    private var header: some View {
        VStack(spacing: RAWDeskTokens.Spacing.medium) {
            HStack(
                alignment: .center,
                spacing: RAWDeskTokens.Spacing.medium
            ) {
                VStack(
                    alignment: .leading,
                    spacing: RAWDeskTokens.Spacing.xSmall
                ) {
                    Text("People")
                        .font(
                            RAWDeskTokens.Typography
                                .workspaceHeader
                        )
                    Label(
                        "Face analysis and matching stay on this Mac",
                        systemImage: "lock.shield"
                    )
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                }

                Spacer()

                PeopleMetric(
                    value: people.namedPersonCount,
                    label: "Named"
                )
                PeopleMetric(
                    value: people.unconfirmedFaceCount,
                    label: "To Review"
                )
                PeopleMetric(
                    value: people.activeFaceCount,
                    label: "Faces"
                )
            }

            HStack(spacing: RAWDeskTokens.Spacing.small) {
                Label(
                    "Suggestions never apply a name until you confirm them",
                    systemImage: "checkmark.shield"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )

                Spacer()
                Text("Grouping")
                    .font(RAWDeskTokens.Typography.metadata)
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                Picker(
                    "Grouping sensitivity",
                    selection: $people.groupingSensitivity
                ) {
                    ForEach(
                        PeopleGroupingSensitivity.allCases
                    ) { sensitivity in
                        Text(sensitivity.name)
                            .tag(sensitivity)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)

                if people.isScanning {
                    Button {
                        if people.isAutomaticScan {
                            people.setAutomaticAnalysisEnabled(
                                false
                            )
                        } else {
                            people.cancelScan()
                        }
                    } label: {
                        Label(
                            people.isAutomaticScan
                                ? "Pause"
                                : "Cancel",
                            systemImage:
                                people.isAutomaticScan
                                ? "pause"
                                : "xmark"
                        )
                    }
                } else {
                    Button {
                        people.startScan(forceReanalysis: true)
                    } label: {
                        Label(
                            "Analyze Again",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .help(
                        "Re-detect faces while preserving reviewed names where the same face can be matched."
                    )
                }
            }
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.medium
            )
            .frame(
                height:
                    RAWDeskTokens.Size
                        .workspaceControlBar
            )

            Divider()

            HStack(spacing: RAWDeskTokens.Spacing.medium) {
                Image(
                    systemName:
                        "person.crop.rectangle.stack.badge.plus"
                )
                .font(
                    RAWDeskTokens.Typography
                        .workspaceHeader
                )
                .foregroundStyle(
                    people.automaticAnalysisEnabled
                        ? RAWDeskTokens.ColorToken.selection
                        : RAWDeskTokens.ColorToken
                            .textSecondary
                )

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text("Background People Analysis")
                        .font(
                            RAWDeskTokens.Typography
                                .sectionHeader
                        )
                    if let message =
                        people.backgroundStatusMessage {
                        Text(message)
                            .font(
                                RAWDeskTokens
                                    .Typography.metadata
                            )
                            .foregroundStyle(
                                RAWDeskTokens.ColorToken
                                    .warning
                            )
                            .lineLimit(2)
                    } else {
                        Text(
                            people.automaticAnalysisEnabled
                                ? "Checks new or changed catalog photos while RAWDesk is active. Suggestions stay local and unnamed."
                                : "Off by default. Analysis runs only when you open People or choose Analyze Again."
                        )
                        .font(
                            RAWDeskTokens.Typography
                                .metadata
                        )
                        .foregroundStyle(
                            RAWDeskTokens.ColorToken
                                .textSecondary
                        )
                        .lineLimit(2)
                    }
                }

                Spacer(
                    minLength:
                        RAWDeskTokens.Spacing.medium
                )

                Toggle(
                    "Analyze new photos",
                    isOn: automaticAnalysisBinding
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityIdentifier(
                    "Automatic People analysis"
                )
            }
            .padding(
                .horizontal,
                RAWDeskTokens.Spacing.medium
            )
            .padding(.vertical, RAWDeskTokens.Spacing.small)

            Divider()

            if let progress = people.scanProgress {
                HStack(
                    spacing:
                        RAWDeskTokens.Spacing.small
                ) {
                    ProgressView(
                        value: progress.fractionCompleted
                    )
                    .frame(maxWidth: 220)
                    Text(
                        (
                            people.isAutomaticScan
                                ? "Background · "
                                : ""
                        )
                            + (
                                progress.filename
                                    ?? "Preparing analysis…"
                            )
                    )
                        .lineLimit(1)
                    Spacer()
                    Text(
                        "\(progress.completed) of \(progress.total) · \(progress.faceCount) faces"
                    )
                    .monospacedDigit()
                }
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        "People analysis \(progress.completed) of \(progress.total), \(progress.faceCount) faces"
                    )
                )
            }
        }
        .padding(RAWDeskTokens.Spacing.large)
        .background(RAWDeskTokens.ColorToken.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RAWDeskTokens.ColorToken.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if people.isScanning && people.activeFaceCount == 0 {
            PeopleInitialScanView(progress: people.scanProgress)
        } else if people.activeFaceCount == 0 {
            RAWEmptyState(
                title: "No Faces Found",
                systemImage: "person.crop.rectangle",
                message:
                    people.lastScanResult?.candidateCount == 0
                    ? "Add photos to the catalog, then return to People."
                    : "No reviewable faces were detected in the catalog photos."
            ) {
                Button("Analyze Again") {
                    people.startScan(forceReanalysis: true)
                }
            }
        } else {
            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing:
                        RAWDeskTokens.Spacing.xLarge
                ) {
                    if !people.visibleNamedGroups.isEmpty {
                        peopleSection(
                            title: "Named People",
                            subtitle:
                                "Confirmed names are never changed by automatic grouping.",
                            groups: people.visibleNamedGroups
                        )
                    }

                    if !people.visibleSuggestedGroups.isEmpty {
                        peopleSection(
                            title: "Suggested Matches",
                            subtitle:
                                "Visual-similarity candidates only. Review before naming or adding to a person.",
                            groups:
                                people.visibleSuggestedGroups,
                            suggested: true
                        )
                    }

                    if !people.visibleSingleFaces.isEmpty {
                        singleFacesSection
                    }

                    if people.snapshot.ignoredFaceCount > 0 {
                        HStack {
                            Label(
                                "\(people.snapshot.ignoredFaceCount) ignored face\(people.snapshot.ignoredFaceCount == 1 ? "" : "s")",
                                systemImage: "eye.slash"
                            )
                            .foregroundStyle(
                                RAWDeskTokens.ColorToken
                                    .textSecondary
                            )
                            Spacer()
                            Button("Restore Ignored Faces") {
                                people.restoreIgnoredFaces()
                            }
                        }
                        .font(
                            RAWDeskTokens.Typography
                                .metadata
                        )
                        .padding(
                            .vertical,
                            RAWDeskTokens.Spacing.small
                        )
                    }
                }
                .padding(RAWDeskTokens.Spacing.xLarge)
            }
        }
    }

    private func peopleSection(
        title: String,
        subtitle: String,
        groups: [PeopleGroup],
        suggested: Bool = false
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.medium
        ) {
            sectionHeading(
                title: title,
                subtitle: subtitle,
                symbol:
                    suggested
                        ? "sparkles.rectangle.stack"
                        : "person.2.fill"
            )
            LazyVGrid(
                columns: personColumns,
                alignment: .leading,
                spacing:
                    RAWDeskTokens.Spacing.large
            ) {
                ForEach(groups) { group in
                    PersonGroupCard(
                        people: people,
                        group: group,
                        selected:
                            people.selectedGroupID == group.id
                    )
                }
            }
        }
    }

    private var singleFacesSection: some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.medium
        ) {
            sectionHeading(
                title: "Unconfirmed Faces",
                subtitle:
                    "These faces did not form a conservative multi-photo match.",
                symbol: "person.crop.square"
            )
            LazyVGrid(
                columns: faceColumns,
                alignment: .leading,
                spacing:
                    RAWDeskTokens.Spacing.medium
            ) {
                ForEach(people.visibleSingleFaces) { face in
                    SingleFaceCard(
                        people: people,
                        face: face,
                        selected:
                            people.selectedFaceID == face.id
                    )
                }
            }
        }
    }

    private func sectionHeading(
        title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: RAWDeskTokens.Spacing.small) {
            Image(systemName: symbol)
                .foregroundStyle(RAWDeskTokens.ColorToken.selection)
            Text(title)
                .font(
                    RAWDeskTokens.Typography
                        .workspaceHeader
                )
            Text(subtitle)
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
            Spacer()
        }
    }
}

private struct PeopleMetric: View {
    var value: Int
    var label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: RAWDeskTokens.Spacing.xSmall) {
            Text("\(value)")
                .font(RAWDeskTokens.Typography.numeric)
                .monospacedDigit()
            Text(label)
                .font(RAWDeskTokens.Typography.badge)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PeopleInitialScanView: View {
    var progress: PeopleScanProgress?

    var body: some View {
        RAWEmptyState(
            title: "Finding faces on this Mac",
            indicator: .progress,
            message: "RAWDesk stores reviewable face rectangles and visual-similarity descriptors in the local catalog. It does not upload photos or assign names automatically."
        ) {
            if let progress {
                Text(
                    "\(progress.completed) of \(progress.total) photos"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .monospacedDigit()
                .foregroundStyle(
                    RAWDeskTokens.ColorToken
                        .textSecondary
                )
            }
        }
    }
}

private struct PersonGroupCard: View {
    @ObservedObject var people: PeopleViewModel
    var group: PeopleGroup
    var selected: Bool

    var body: some View {
        Button {
            people.selectGroup(group)
        } label: {
            VStack(
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.small
            ) {
                ZStack(alignment: .topTrailing) {
                    if let face = group.representativeFace,
                       let asset = people.asset(for: face) {
                        FaceCropThumbnailView(
                            asset: asset,
                            face: face,
                            target: 420
                        )
                    } else {
                        RoundedRectangle(
                            cornerRadius:
                                RAWDeskTokens.Radius
                                    .group
                        )
                            .fill(
                                RAWDeskTokens.ColorToken
                                    .controlElevated
                            )
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 38))
                                    .foregroundStyle(
                                        RAWDeskTokens
                                            .ColorToken
                                            .textSecondary
                                    )
                            }
                    }

                    if group.isSuggested {
                        RAWStateBadge(
                            text: "Suggested",
                            systemImage: "sparkles",
                            tone: .neutral
                        )
                        .padding(
                            RAWDeskTokens.Spacing
                                .small
                        )
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(alignment: .leading, spacing: RAWDeskTokens.Spacing.xSmall) {
                    Text(group.name)
                        .font(
                            RAWDeskTokens.Typography
                                .sectionHeader
                        )
                        .lineLimit(1)
                    Text(
                        "\(group.faces.count) face\(group.faces.count == 1 ? "" : "s") · \(group.photoCount) photo\(group.photoCount == 1 ? "" : "s")"
                    )
                    .font(
                        RAWDeskTokens.Typography
                            .metadata
                    )
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
                    .monospacedDigit()
                }
            }
            .padding(RAWDeskTokens.Spacing.small)
            .background(
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.group
                )
                    .fill(
                        RAWDeskTokens.ColorToken.panel
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.group
                )
                    .stroke(
                        selected
                            ? RAWDeskTokens.ColorToken.selection
                            : RAWDeskTokens.ColorToken
                                .divider,
                        style:
                            group.isSuggested
                            ? StrokeStyle(
                                lineWidth: selected ? 2 : 1,
                                dash: [6, 4]
                            )
                            : StrokeStyle(
                                lineWidth: selected ? 2 : 1
                            )
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                "\(group.name), \(group.faces.count) faces in \(group.photoCount) photos\(group.isSuggested ? ", suggested match" : "")"
            )
        )
    }
}

private struct SingleFaceCard: View {
    @ObservedObject var people: PeopleViewModel
    var face: CatalogFace
    var selected: Bool

    var body: some View {
        Button {
            people.selectFace(face)
        } label: {
            VStack(
                alignment: .leading,
                spacing: RAWDeskTokens.Spacing.small
            ) {
                if let asset = people.asset(for: face) {
                    FaceCropThumbnailView(
                        asset: asset,
                        face: face,
                        target: 300
                    )
                    .aspectRatio(1, contentMode: .fit)
                }
                Text(people.filename(for: face))
                    .font(
                        RAWDeskTokens.Typography
                            .metadata
                    )
                    .lineLimit(1)
            }
            .padding(RAWDeskTokens.Spacing.small)
            .background(
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.group
                )
                    .fill(
                        RAWDeskTokens.ColorToken.panel
                    )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius:
                        RAWDeskTokens.Radius.group
                )
                    .stroke(
                        selected ? RAWDeskTokens.ColorToken.selection : .clear,
                        lineWidth: 2
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text("Unconfirmed face in \(people.filename(for: face))")
        )
    }
}

struct PeopleInspectorView: View {
    @ObservedObject var people: PeopleViewModel
    @ObservedObject var library: LibraryViewModel

    @State private var nameDraft = ""
    @State private var confirmDeletePerson = false

    var body: some View {
        Group {
            if let group = people.selectedGroup {
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing:
                            RAWDeskTokens.Spacing.large
                    ) {
                        groupSummary(group)
                        Divider()
                        faceCollection(group)
                        if let face = people.selectedFace {
                            Divider()
                            faceDetails(face)
                        }
                        if people.snapshot.ignoredFaceCount > 0 {
                            Divider()
                            Button("Restore All Ignored Faces") {
                                people.restoreIgnoredFaces()
                            }
                        }
                    }
                    .padding(
                        RAWDeskTokens.Spacing.large
                    )
                }
            } else {
                RAWEmptyState(
                    title: "Choose a Person",
                    systemImage: "person.crop.square",
                    message:
                        "Select a named person, suggested group, or unconfirmed face to review it."
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .onAppear { updateNameDraft() }
        .onChange(of: people.selectedGroupID) { _, _ in
            updateNameDraft()
        }
        .confirmationDialog(
            "Remove this named person?",
            isPresented: $confirmDeletePerson,
            titleVisibility: .visible
        ) {
            Button("Remove Person", role: .destructive) {
                people.deleteSelectedPerson()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The name will be removed. Its faces return to review; no photo or sidecar is changed."
            )
        }
    }

    private func groupSummary(
        _ group: PeopleGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.medium
        ) {
            if let face = group.representativeFace,
               let asset = people.asset(for: face) {
                FaceCropThumbnailView(
                    asset: asset,
                    face: face,
                    target: 520
                )
                .aspectRatio(1.1, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }

            if group.isSuggested {
                Label(
                    group.faces.count > 1
                        ? "Reviewable similarity suggestion"
                        : "Unconfirmed face",
                    systemImage: "sparkles"
                )
                .font(RAWDeskTokens.Typography.metadata)
                .foregroundStyle(
                    RAWDeskTokens.ColorToken.textSecondary
                )
            }

            TextField("Person name", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveName(group) }

            Button {
                saveName(group)
            } label: {
                Label(
                    group.personID == nil
                        ? "Name This Person"
                        : "Save Name",
                    systemImage:
                        group.personID == nil
                            ? "person.crop.circle.badge.plus"
                            : "checkmark"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()
            .disabled(
                nameDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )

            if group.personID == nil,
               !people.snapshot.namedGroups.isEmpty {
                Menu {
                    ForEach(people.snapshot.namedGroups) {
                        destination in
                        if let personID = destination.personID {
                            Button(destination.name) {
                                people.assignGroup(
                                    group,
                                    to: personID
                                )
                            }
                        }
                    }
                } label: {
                    Label(
                        "Add to Existing Person",
                        systemImage: "person.2.badge.gearshape"
                    )
                    .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)

                Button(role: .destructive) {
                    people.ignoreGroup(group)
                } label: {
                    Label(
                        group.faces.count == 1
                            ? "Not a Face"
                            : "Ignore This Group",
                        systemImage: "eye.slash"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if group.personID != nil {
                Menu {
                    ForEach(people.mergeDestinations) {
                        destination in
                        Button(destination.name) {
                            people.mergeSelectedPerson(
                                into: destination.id
                            )
                        }
                    }
                } label: {
                    Label(
                        "Merge with Person",
                        systemImage: "arrow.triangle.merge"
                    )
                    .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .disabled(people.mergeDestinations.isEmpty)

                Button(role: .destructive) {
                    confirmDeletePerson = true
                } label: {
                    Label(
                        "Remove Person",
                        systemImage: "person.crop.circle.badge.minus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Text(
                "\(group.faces.count) face\(group.faces.count == 1 ? "" : "s") across \(group.photoCount) photo\(group.photoCount == 1 ? "" : "s")"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )
            .monospacedDigit()
        }
    }

    private func faceCollection(
        _ group: PeopleGroup
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Text("Faces")
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 66),
                        spacing:
                            RAWDeskTokens.Spacing.small
                    )
                ],
                spacing: RAWDeskTokens.Spacing.small
            ) {
                ForEach(group.faces) { face in
                    Button {
                        people.selectFace(face)
                    } label: {
                        if let asset = people.asset(for: face) {
                            FaceCropThumbnailView(
                                asset: asset,
                                face: face,
                                target: 180
                            )
                            .aspectRatio(1, contentMode: .fill)
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius:
                                        RAWDeskTokens.Radius
                                            .group
                                )
                                    .stroke(
                                        people.selectedFaceID == face.id
                                            ? RAWDeskTokens.ColorToken.selection
                                            : .clear,
                                        lineWidth: 2
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text(
                            "Face in \(people.filename(for: face))"
                        )
                    )
                }
            }
        }
    }

    private func faceDetails(
        _ face: CatalogFace
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: RAWDeskTokens.Spacing.small
        ) {
            Text("Selected Face")
                .font(
                    RAWDeskTokens.Typography
                        .sectionHeader
                )
            LabeledContent("Photo") {
                Text(people.filename(for: face))
                    .lineLimit(1)
            }
            LabeledContent("Detection") {
                Text(
                    face.confidence,
                    format: .percent.precision(.fractionLength(0))
                )
            }
            if let quality = face.captureQuality {
                LabeledContent("Capture quality") {
                    Text(
                        quality,
                        format:
                            .percent.precision(.fractionLength(0))
                    )
                }
            }
            Label(
                "Name and face decisions stay in the catalog. The image and XMP remain untouched.",
                systemImage: "externaldrive.badge.checkmark"
            )
            .font(RAWDeskTokens.Typography.metadata)
            .foregroundStyle(
                RAWDeskTokens.ColorToken.textSecondary
            )

            Button {
                library.showCatalogPhoto(id: face.photoID)
            } label: {
                Label(
                    "Show Photo in Library",
                    systemImage: "photo"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .rawPrimaryButtonHeight()

            if face.personID != nil {
                Button {
                    people.unassignFace(face)
                } label: {
                    Label(
                        "Remove from This Person",
                        systemImage: "person.badge.minus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                people.ignoreFace(face)
            } label: {
                Label(
                    "Not a Face",
                    systemImage: "eye.slash"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func saveName(_ group: PeopleGroup) {
        people.nameGroup(group, name: nameDraft)
    }

    private func updateNameDraft() {
        let group = people.selectedGroup
        nameDraft =
            group?.personID == nil
                ? ""
                : group?.name ?? ""
    }
}

struct FaceCropThumbnailView: View {
    var asset: PhotoAsset
    var face: CatalogFace
    var target: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.group
            )
                .fill(
                    LinearGradient(
                        colors: [
                            RAWDeskTokens.ColorToken
                                .controlElevated
                                .opacity(0.5),
                            RAWDeskTokens.ColorToken
                                .controlElevated,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "person.crop.square")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        RAWDeskTokens.ColorToken
                            .textSecondary
                    )
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius:
                    RAWDeskTokens.Radius.group
            )
        )
        .task(id: cacheID) {
            await load()
        }
        .accessibilityHidden(true)
    }

    private var cacheID: String {
        "\(asset.id)|\(face.id)|\(Int(target))"
    }

    @MainActor
    private func load() async {
        image = nil
        failed = false
        let outcome = await ImageLoader.shared.load(
            asset: asset,
            kind: .thumbnail(target: target)
        )
        guard !Task.isCancelled,
              let source = outcome.image,
              let crop = Self.faceCrop(
                  source,
                  bounds: face.boundingBox
              ) else {
            failed = true
            return
        }
        image = crop
    }

    private static func faceCrop(
        _ image: NSImage,
        bounds: CGRect
    ) -> NSImage? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        let padded = expanded(bounds)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let pixelRect = CGRect(
            x: padded.minX * width,
            y: (1 - padded.maxY) * height,
            width: padded.width * width,
            height: padded.height * height
        )
        .integral
        .intersection(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        guard !pixelRect.isNull,
              let cropped = cgImage.cropping(to: pixelRect) else {
            return nil
        }
        return NSImage(
            cgImage: cropped,
            size: NSSize(
                width: cropped.width,
                height: cropped.height
            )
        )
    }

    private static func expanded(_ rect: CGRect) -> CGRect {
        let horizontal = rect.width * 0.32
        let bottom = rect.height * 0.28
        let top = rect.height * 0.46
        let minX = max(0, rect.minX - horizontal)
        let maxX = min(1, rect.maxX + horizontal)
        let minY = max(0, rect.minY - bottom)
        let maxY = min(1, rect.maxY + top)
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}
