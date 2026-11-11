import SwiftUI
import UIKit

struct FabHomeView: View {
    @EnvironmentObject private var store: FabStore
    @State private var addingJob = false
    @State private var jobName = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.jobs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.largeTitle).foregroundColor(.blue)
                            Text("Start your first fabrication request").font(.headline)
                            Text("Create a job, organize fittings by area, then export a shop-ready PDF.")
                                .foregroundColor(.secondary)
                            Button("Create Job") { addingJob = true }.buttonStyle(.borderedProminent)
                        }.padding(.vertical, 16)
                    }
                    ForEach(store.jobs) { job in
                        NavigationLink {
                            FabJobView(jobID: job.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.name).font(.headline)
                                Text("\(job.areas.count) areas  ·  \(job.fittings.count) fittings")
                                    .font(.caption).foregroundColor(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                    .onDelete { indices in
                        let ids = indices.map { store.jobs[$0].id }
                        ids.forEach { store.removeJob($0) }
                    }
                } header: { Text("Jobs") }
            }
            .navigationTitle("ProMetalsFab")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button { jobName = ""; addingJob = true } label: {
                    Text("＋ Add Job").fontWeight(.semibold).fixedSize(horizontal: true, vertical: false)
                }
            }}
            .alert("New Job", isPresented: $addingJob) {
                TextField("Job name", text: $jobName)
                Button("Create") {
                    let trimmed = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { _ = store.createJob(trimmed) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Example: Independence City Center") }
            .alert("Storage Error", isPresented: Binding(get: { store.saveError != nil }, set: { if !$0 { store.saveError = nil } })) {
                Button("OK") { store.saveError = nil }
            } message: { Text(store.saveError ?? "") }
        }
    }
}

struct FabJobView: View {
    @EnvironmentObject private var store: FabStore
    let jobID: UUID
    @State private var creatingArea = false
    @State private var editingArea: FabArea?
    @State private var shareFile: FabExportFile?
    @State private var exportError: String?
    private var job: FabJob? { store.job(jobID) }
    var body: some View {
        List {
            if let job = job {
                Section("Fabrication Requests") {
                    // Hide the old job-root row unless existing fittings need a safe place to access them.
                    // Deleting an area moves its fittings here; never silently hide saved data.
                    if !job.fittings(in: nil).isEmpty {
                        NavigationLink {
                            FabAreaFittingsView(jobID: jobID, areaID: nil)
                        } label: {
                            Label("Fittings to Assign (\(job.fittings(in: nil).count))", systemImage: "tray.full")
                        }
                    }
                    ForEach(job.areas) { area in
                        HStack {
                            NavigationLink {
                                FabAreaFittingsView(jobID: jobID, areaID: area.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(area.name).font(.headline)
                                    Text("\(job.fittings(in: area.id).count) fittings").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Button { editingArea = area } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(.borderless).accessibilityLabel("Area settings")
                        }
                    }
                    .onDelete { offsets in
                        var modified = job
                        let removedIDs = offsets.map { modified.areas[$0].id }
                        modified.areas.removeAll { removedIDs.contains($0.id) }
                        // Deleting an area moves fittings to the job root, never discards them.
                        for index in modified.fittings.indices where removedIDs.contains(modified.fittings[index].areaID ?? UUID()) {
                            modified.fittings[index].areaID = nil
                        }
                        store.replace(modified)
                    }
                }
                Section("Export") {
                    Button { export(job, areaID: nil) } label: {
                        Label("Export Entire Job PDF", systemImage: "doc.richtext")
                    }.disabled(job.fittings.isEmpty)
                    Text("Portrait · 4 fittings per page · drawings + shop specifications")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(job?.name ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
            Button { creatingArea = true } label: {
                Text("＋ Add Area").fontWeight(.semibold).fixedSize(horizontal: true, vertical: false)
            }
        }}
        .sheet(isPresented: $creatingArea) {
            FabAreaEditor(area: FabArea(name: "")) { saved in
                guard var changed = job else { return }
                changed.areas.append(saved)
                store.replace(changed)
            }
        }
        .sheet(item: $editingArea) { area in
            FabAreaEditor(area: area) { saved in
                guard var changed = job, let i = changed.areas.firstIndex(where: { $0.id == saved.id }) else { return }
                changed.areas[i] = saved
                store.replace(changed)
            }
        }
        .sheet(item: $shareFile) { item in FabShareSheet(items: [item.url]) }
        .alert("PDF Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }
    private func export(_ job: FabJob, areaID: UUID?) {
        do { shareFile = FabExportFile(url: try FabPDFExporter.export(job: job, areaID: areaID, includeAllAreas: true)) }
        catch { exportError = error.localizedDescription }
    }
}

struct FabAreaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var area: FabArea
    @State private var showAreaValidation = false
    let onSave: (FabArea) -> Void
    init(area: FabArea, onSave: @escaping (FabArea) -> Void) {
        _area = State(initialValue: area); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Area") { TextField("Area name", text: $area.name) }
                Section("Default Material & Gauge — All Fittings") {
                    Picker("Material", selection: Binding(
                        get: { area.defaultMaterial }, set: { area.material = $0 }
                    )) {
                        ForEach(FabMaterial.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Gauge", selection: Binding(
                        get: { area.defaultGauge }, set: { area.gauge = $0 }
                    )) {
                        ForEach(FabGauge.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if area.defaultGauge == .custom {
                        TextField("Custom gauge or thickness", text: Binding(
                            get: { area.customGauge ?? "" },
                            set: { area.customGauge = $0 }
                        ))
                    }
                    Text("New fittings inherit these values. Existing fittings with no overrides also follow changes to area defaults.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Rectangular fittings — liner") {
                    Picker("Default liner", selection: $area.rectangularLiner) {
                        ForEach(FabLiner.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Round fittings — insulation") {
                    Picker("Default type", selection: $area.roundInsulation) {
                        ForEach(FabRoundInsulation.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if area.roundInsulation != .none {
                        Picker("Default thickness", selection: $area.roundThickness) {
                            ForEach(FabThickness.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
                Section {
                    Text("Fittings using area defaults follow these settings. Fittings with their own insulation override keep their custom specifications. Entered duct sizes never change.")
                        .foregroundColor(.secondary).font(.footnote)
                }
            }
            .navigationTitle(area.name.isEmpty ? "New Area" : "Area Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let validName = !area.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let validGauge = area.defaultGauge != .custom ||
                        !(area.customGauge ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if validName && validGauge { onSave(area); dismiss() }
                    else { showAreaValidation = true }
                }}
            }
            .alert("Check Area Defaults", isPresented: $showAreaValidation) {
                Button("OK") {}
            } message: {
                Text("Enter an area name and, when Custom is selected, a custom gauge or thickness.")
            }
        }
    }
}

struct FabAreaFittingsView: View {
    @EnvironmentObject private var store: FabStore
    let jobID: UUID
    let areaID: UUID?
    @State private var adding = false
    @State private var editing: FabFitting?
    @State private var shareFile: FabExportFile?
    @State private var exportError: String?
    private var job: FabJob? { store.job(jobID) }
    private var area: FabArea? { job?.areas.first { $0.id == areaID } }
    private var list: [FabFitting] { job?.fittings(in: areaID) ?? [] }
    var body: some View {
        List {
            Section {
                if list.isEmpty {
                    Text("No fittings yet. Tap Add Fitting to create your first fitting.")
                        .foregroundColor(.secondary)
                }
                ForEach(list) { fitting in
                    Button { editing = fitting } label: {
                        HStack(spacing: 12) {
                            FabFittingListIcon(fitting: fitting)
                                .frame(width: 52, height: 48)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fitting.name.isEmpty ? fitting.shape.displayName : fitting.name)
                                    .font(.headline).foregroundColor(.primary)
                                Text(fitting.shape.displayName + " · Qty \(fitting.quantity)")
                                    .font(.caption).foregroundColor(.secondary)
                                Text(fitting.isRound ? "Ø \(fabInches(fitting.inletWidth))" : "\(fabInches(fitting.inletWidth)) × \(fabInches(fitting.inletHeight))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
                .onDelete { offsets in
                    guard var changed = job else { return }
                    let ids = offsets.map { list[$0].id }
                    changed.fittings.removeAll { ids.contains($0.id) }
                    store.replace(changed)
                }
                .onMove { from, to in
                    guard var changed = job else { return }
                    var reordered = list
                    reordered.move(fromOffsets: from, toOffset: to)
                    let ids = Set(reordered.map(\.id))
                    var iter = reordered.makeIterator()
                    for index in changed.fittings.indices where ids.contains(changed.fittings[index].id) {
                        if let next = iter.next() { changed.fittings[index] = next }
                    }
                    store.replace(changed)
                }
            } header: { Text("\(list.count) fittings") }
            if let job = job, !list.isEmpty {
                Section {
                    Button { export(job) } label: {
                        Label("Export \(area?.name ?? "Fittings to Assign") PDF", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(area?.name ?? "Fittings to Assign")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { adding = true } label: {
                    Text("＋ Add Fitting").fontWeight(.semibold).fixedSize(horizontal: true, vertical: false)
                }
            }
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
        .sheet(isPresented: $adding) {
            FabNewFittingFlow(areaID: areaID, area: area) { new in
                guard var changed = job else { return }
                changed.fittings.append(new); store.replace(changed)
            }
        }
        .sheet(item: $editing) { fitting in
            NavigationStack {
                FabFittingEditor(fitting: fitting, area: area) { saved in
                    guard var changed = job, let index = changed.fittings.firstIndex(where: { $0.id == saved.id }) else { return }
                    changed.fittings[index] = saved
                    store.replace(changed)
                }
            }
        }
        .sheet(item: $shareFile) { FabShareSheet(items: [$0.url]) }
        .alert("PDF Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }
    private func export(_ job: FabJob) {
        do { shareFile = FabExportFile(url: try FabPDFExporter.export(job: job, areaID: areaID)) }
        catch { exportError = error.localizedDescription }
    }
}

struct FabNewFittingFlow: View {
    @Environment(\.dismiss) private var dismiss
    let areaID: UUID?
    let area: FabArea?
    let onSave: (FabFitting) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("RECTANGULAR").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    grid(FabShape.libraryChoices.filter { !$0.isRound && !$0.isCustom })
                    Text("ROUND").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    grid(FabShape.libraryChoices.filter(\.isRound))
                    Text("SPECIAL REQUEST").font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    grid([.custom])
                    Text("Select a fitting to enter its dimensions. Labels match each shop drawing.")
                        .font(.footnote).foregroundColor(.secondary)
                }.padding(16)
            }
            .navigationTitle("Select Fitting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }}
        }
    }
    private func grid(_ shapes: [FabShape]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(shapes) { shape in
                NavigationLink {
                    FabFittingEditor(fitting: .new(shape: shape, areaID: areaID), area: area,
                                     dismissAfterSave: false) { new in
                        onSave(new)
                        dismiss() // Dismiss the whole selection sheet, only once.
                    }
                } label: {
                    VStack(spacing: 7) {
                        FabFittingGlyph(shape: shape)
                            .frame(height: 94)
                            .padding(.horizontal, 8)
                        Text(shape.displayName)
                            .font(.subheadline).fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 34)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FabFittingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fitting: FabFitting
    let area: FabArea?
    let onSave: (FabFitting) -> Void
    let dismissAfterSave: Bool
    @State private var showError = false
    @State private var show3DPreview = false
    @State private var customizedTransition = false
    @FocusState private var dimensionFocused: Bool

    init(fitting: FabFitting, area: FabArea?, dismissAfterSave: Bool = true,
         onSave: @escaping (FabFitting) -> Void) {
        var editable = fitting
        if editable.isRound && !editable.shape.isHeto {
            // Normalize V1 labels without breaking existing saved connections.
            if editable.inletConnection == .flanged && editable.inletSpecial.isEmpty {
                editable.inletSpecial = "Flanged"
            }
            if editable.outletConnection == .flanged && editable.outletSpecial.isEmpty {
                editable.outletSpecial = "Flanged"
            }
            editable.inletConnection = editable.inletConnection.normalizedRound
            editable.outletConnection = editable.outletConnection.normalizedRound
        }
        if !editable.isRound {
            if editable.inletConnection == .special {
                editable.inletConnection = .custom
            }
            if editable.outletConnection == .special {
                editable.outletConnection = .custom
            }
        }
        if editable.shape == .squareRound {
            let existing = editable.outletConnection.normalizedRound
            if FabConnection.round.contains(existing) {
                editable.outletConnection = existing
            } else {
                if editable.outletSpecial.isEmpty { editable.outletSpecial = existing.rawValue }
                editable.outletConnection = .custom
            }
        }
        _fitting = State(initialValue: editable)
        _customizedTransition = State(initialValue: editable.shape == .rectTransition &&
            (editable.verticalAlignment != .centered || editable.horizontalAlignment != .centered))
        self.area = area
        self.dismissAfterSave = dismissAfterSave
        self.onSave = onSave
    }
    private var isRound: Bool { fitting.isRound }
    private var isRoundElbow: Bool { fitting.shape.isRoundElbow }
    private var isRectElbow: Bool { fitting.shape.isRectElbow }
    private var inConnections: [FabConnection] {
        if fitting.shape.isHeto { return FabConnection.rectangular }
        if fitting.shape.isRoundSpiral { return FabConnection.spiral }
        return isRound ? FabConnection.round : FabConnection.rectangular
    }
    private var outConnections: [FabConnection] {
        if fitting.shape.isRoundSpiral { return FabConnection.spiral }
        return (isRound || fitting.shape == .squareRound) ? FabConnection.round : FabConnection.rectangular
    }
    private var isSquareElbow: Bool { fitting.shape.isSquareElbow }
    private var isTransition: Bool { fitting.shape == .rectTransition }
    private var isTee: Bool { fitting.shape == .rectTee }
    private var isEndCap: Bool { fitting.shape.singleOpening }
    private var materialSelection: Binding<FabMaterial> {
        Binding(get: { fitting.effectiveMaterial(in: area) }, set: { fitting.materialOverride = $0 })
    }
    private var gaugeSelection: Binding<FabGauge> {
        Binding(get: { fitting.effectiveGauge(in: area) }, set: { fitting.gaugeOverride = $0 })
    }
    private var customGaugeText: Binding<String> {
        Binding(get: {
            fitting.gaugeOverride == nil ? (area?.customGauge ?? "") : (fitting.customGaugeOverride ?? "")
        }, set: { fitting.customGaugeOverride = $0 })
    }
    private var elbowFabricationSelection: Binding<FabElbowFabrication> {
        Binding(get: { fitting.fabricationType }, set: { fitting.elbowFabrication = $0 })
    }
    private var radiusFactorSelection: Binding<FabRadiusFactor> {
        Binding(get: { fitting.radiusFactor }, set: { fitting.elbowRadiusFactor = $0 })
    }
    private var reducerAlignmentSelection: Binding<FabReducerAlignment> {
        Binding(get: { fitting.reducerMode }, set: { fitting.reducerAlignment = $0 })
    }
    private var hetoLengthSelection: Binding<FabHetoLengthMode> {
        Binding(get: { fitting.hetoMode }, set: { fitting.hetoLengthMode = $0 })
    }
    private var teeE: Binding<Double> { Binding(get: { fitting.teeE }, set: { fitting.teeRightWidth = $0 }) }
    private var teeF: Binding<Double> { Binding(get: { fitting.teeF }, set: { fitting.teeRightDepth = $0 }) }
    private var teeG: Binding<Double> { Binding(get: { fitting.teeG }, set: { fitting.teeThroatG = $0 }) }
    private var teeH: Binding<Double> { Binding(get: { fitting.teeH }, set: { fitting.teeThroatH = $0 }) }
    private var teeI: Binding<Double> { Binding(get: { fitting.teeI }, set: { fitting.teeThroatI = $0 }) }
    private var teeJ: Binding<Double> { Binding(get: { fitting.teeJ }, set: { fitting.teeThroatJ = $0 }) }
    private var teeRightConnection: Binding<FabConnection> {
        Binding(get: { fitting.teeRightConnection ?? .slipDrive }, set: { fitting.teeRightConnection = $0 })
    }
    private var teeRightSpecial: Binding<String> {
        Binding(get: { fitting.teeRightSpecial ?? "" }, set: { fitting.teeRightSpecial = $0 })
    }
    private var damper: Binding<Bool> {
        Binding(get: { fitting.isDampered }, set: { fitting.hasDamper = $0 })
    }
    private var diameterInput: Binding<Double> {
        Binding(get: { fitting.inletWidth }, set: { newValue in
            fitting.inletWidth = newValue
            fitting.inletHeight = newValue
            if fitting.shape.isRoundElbow || fitting.shape == .roundStraight || fitting.shape.isRoundSpiral {
                fitting.outletWidth = newValue
                fitting.outletHeight = newValue
            }
        })
    }
    private var rectangularWidth: Binding<Double> {
        Binding(get: { fitting.inletWidth }, set: { newValue in
            fitting.inletWidth = newValue
            if fitting.shape == .rectStraight { fitting.outletWidth = newValue }
        })
    }
    private var rectangularDepth: Binding<Double> {
        Binding(get: { fitting.inletHeight }, set: { newValue in
            fitting.inletHeight = newValue
            if fitting.shape == .rectStraight { fitting.outletHeight = newValue }
        })
    }
    private var elbowAngleMode: Binding<String> {
        Binding(get: {
            fitting.angleIsCustom ? "Custom" : (fitting.shape == .roundElbow45 ? "45°" : "90°")
        }, set: { selected in
            if selected == "Custom" {
                fitting.elbowAngleCustom = true
                if fitting.angle <= 0 { fitting.angle = 90 }
            } else {
                fitting.elbowAngleCustom = false
                fitting.shape = selected == "45°" ? .roundElbow45 : .roundElbow90
                fitting.angle = selected == "45°" ? 45 : 90
            }
        })
    }
    private var elbowAngle: Binding<Int> {
        Binding(get: { fitting.shape == .roundElbow45 ? 45 : 90 }, set: { selected in
            fitting.shape = selected == 45 ? .roundElbow45 : .roundElbow90
            fitting.angle = Double(selected)
            fitting.outletWidth = fitting.inletWidth
            fitting.outletHeight = fitting.inletWidth
        })
    }
    private var inputConnection: Binding<FabConnection> {
        Binding(get: { (isRound && !fitting.shape.isHeto) ? fitting.inletConnection.normalizedRound : fitting.inletConnection },
                set: { fitting.inletConnection = $0 })
    }
    private var outputConnection: Binding<FabConnection> {
        Binding(get: { (isRound || fitting.shape == .squareRound) ? fitting.outletConnection.normalizedRound : fitting.outletConnection },
                set: { fitting.outletConnection = $0 })
    }
    private func number(_ title: String, _ value: Binding<Double>, unit: String = "in") -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField(unit == "°" ? "Degrees" : "Inches", value: value, format: .number)
                .keyboardType(.decimalPad)
                .focused($dimensionFocused)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
            Text(unit).foregroundColor(.secondary)
        }
    }
    private func matched(_ title: String, value: Double) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(fabInches(value)).fontWeight(.medium)
            Text("matched").font(.caption2).foregroundColor(.secondary)
        }
    }
    @ViewBuilder
    private var measurementsAndAlignment: some View {
Section("Dimensions — Finished Inches") {
    if isRound {
        if isRoundElbow {
            number("A — Diameter (both ends)", diameterInput)
            Picker("B — Elbow Angle", selection: elbowAngleMode) {
                Text("90°").tag("90°")
                Text("45°").tag("45°")
                Text("Custom").tag("Custom")
            }
            if fitting.angleIsCustom { number("B — Custom Angle", $fitting.angle, unit: "°") }
            Picker("Fabrication", selection: elbowFabricationSelection) {
                ForEach(FabElbowFabrication.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Radius Factor", selection: radiusFactorSelection) {
                ForEach(FabRadiusFactor.allCases) { Text($0.displayName).tag($0) }
            }
        } else if fitting.shape.isRoundReducer {
            number("A — Diameter In", diameterInput)
            number("B — Diameter Out", $fitting.outletWidth)
            number("C — Length", $fitting.length)
            Picker("Offset", selection: reducerAlignmentSelection) {
                ForEach(FabReducerAlignment.allCases) { Text($0.rawValue).tag($0) }
            }
            if fitting.reducerMode == .flatTop {
                Text("Flat Top: top edges stay aligned. Centerline shift is half the diameter difference.")
                    .font(.caption).foregroundColor(.secondary)
            }
        } else if fitting.shape.isHeto {
            number("A — Rectangular Width", $fitting.inletWidth)
            number("B — Rectangular Depth", $fitting.inletHeight)
            number("C — Round Diameter", $fitting.outletWidth)
            Picker("D — Length", selection: hetoLengthSelection) {
                ForEach(FabHetoLengthMode.allCases) { Text($0.rawValue).tag($0) }
            }
            if fitting.needsCustomLength {
                number("D — Custom Length", $fitting.length)
            } else {
                Text("D — STANDARD (determined by opening sizes)")
                    .font(.caption).foregroundColor(.secondary)
            }
        } else if fitting.shape.isRoundSpiral {
            number("A — Pipe Length", $fitting.length)
            number("B — Diameter (both ends)", diameterInput)
        } else if fitting.shape.isRoundEndCap {
            number("A — Diameter", diameterInput)
        } else {
            // Legacy round parts remain editable in pre-V4 saved jobs.
            number("A — Diameter In", diameterInput)
            if fitting.shape == .roundStraight {
                matched("C — Diameter Out", value: fitting.inletWidth)
            } else {
                number("C — Diameter Out", $fitting.outletWidth)
            }
            number("E — Overall Length", $fitting.length)
            if !fitting.shape.isStraight {
                number("K — Straight In", $fitting.straightIn)
                number("L — Straight Out", $fitting.straightOut)
            }
            if fitting.shape == .roundTee {
                number("M — Branch Diameter", $fitting.branchDiameter)
                number("J — Lateral Angle", $fitting.angle, unit: "°")
            }
        }
    } else {
        number(isEndCap || fitting.shape == .squareRound ? "A — Width" : "A — Width In", rectangularWidth)
        number(isEndCap || fitting.shape == .squareRound ? "B — Depth" : "B — Depth In", rectangularDepth)
        if isEndCap { // One opening only, no length required.
        } else if fitting.shape == .rectStraight {
            matched("C — Width Out", value: fitting.inletWidth)
            matched("D — Depth Out", value: fitting.inletHeight)
            number("E — Overall Length", $fitting.length)
        } else if fitting.shape == .squareRound {
            number("C — Round Diameter", $fitting.outletWidth)
            number("D — Overall Length", $fitting.length)
        } else if isTee {
            number("C — Left Width", $fitting.outletWidth)
            number("D — Left Depth", $fitting.outletHeight)
            number("E — Right Width", teeE)
            number("F — Right Depth", teeF)
            number("G — Upper Left Throat", teeG)
            number("H — Lower Left Throat", teeH)
            number("I — Lower Right Throat", teeI)
            number("J — Upper Right Throat", teeJ)
        } else {
            number("C — Width Out", $fitting.outletWidth)
            number("D — Depth Out", $fitting.outletHeight)
            if isSquareElbow {
                number("E — Throat Length 1", $fitting.straightIn)
                number("F — Throat Length 2", $fitting.straightOut)
            } else if fitting.shape == .rectRadiusElbow {
                number("E — Full Interior Radius", $fitting.radius)
                number("F — Top Shift (+up / -down)", $fitting.verticalValue)
                Text("Top and bottom shift together. Specify flat top/bottom in Notes.")
                    .font(.caption).foregroundColor(.secondary)
            } else if isTransition {
                number("Overall Length", $fitting.length)
                number("Straight In", $fitting.straightIn)
                number("Straight Out", $fitting.straightOut)
            } else {
                number("Overall Length", $fitting.length)
                number("Straight In", $fitting.straightIn)
                number("Straight Out", $fitting.straightOut)
            }
        }
    }
}
if isTransition {
    Section("Transition Side Reductions — Linked") {
        Text("Starts centered. Top and Bottom show signed edge movement: + up, − down. Editing one recalculates the other.")
            .font(.caption).foregroundColor(.secondary)
        number("Left", Binding(get: { fitting.transitionLeft }, set: {
            fitting.setTransitionLeft($0); customizedTransition = true
        }))
        number("Right", Binding(get: { fitting.transitionRight }, set: {
            fitting.setTransitionRight($0); customizedTransition = true
        }))
        number("Top (up + / down −)", Binding(get: { fitting.transitionTop }, set: {
            fitting.setTransitionTop($0); customizedTransition = true
        }))
        number("Bottom (up + / down −)", Binding(get: { fitting.transitionBottom }, set: {
            fitting.setTransitionBottom($0); customizedTransition = true
        }))
        Button("Reset to Centerline") {
            fitting.centerTransition(); customizedTransition = false
        }
        Text(customizedTransition ? "Custom alignment" : "Centered alignment")
            .font(.caption).foregroundColor(.secondary)
    }
} else if fitting.shape.isTransition && fitting.shape != .squareRound && !fitting.shape.isCatalogRound {
    // Retain legacy offset controls for previously saved V2 offsets.
    Section("Legacy Alignment and Offsets") {
        Picker("Vertical", selection: $fitting.verticalAlignment) {
            ForEach(FabVerticalAlignment.allCases) { Text($0.rawValue).tag($0) }
        }
        number("Vertical Value", $fitting.verticalValue)
        Picker("Horizontal", selection: $fitting.horizontalAlignment) {
            ForEach(FabHorizontalAlignment.allCases) { Text($0.rawValue).tag($0) }
        }
        number("Horizontal Value", $fitting.horizontalValue)
    }
}
    }
    @ViewBuilder
    private var connectorSection: some View {
Section("Connections") {
    let inletLabel = isTee ? "Bottom (A × B)" :
        ((fitting.shape == .squareRound || fitting.shape.isHeto) ? "Rectangular (A × B)" :
         (isEndCap ? "Open End Connection" : "Connection In"))
    Picker(inletLabel, selection: inputConnection) {
        ForEach(inConnections) { Text($0.rawValue).tag($0) }
    }
    if inputConnection.wrappedValue == .custom || inputConnection.wrappedValue == .special {
        TextField("Custom inlet connection", text: $fitting.inletSpecial)
            .focused($dimensionFocused)
    }
    if !isEndCap {
        let outletLabel = isTee ? "Left (C × D)" :
            ((fitting.shape == .squareRound || fitting.shape.isHeto) ? "Round (C)" : "Connection Out")
        Picker(outletLabel, selection: outputConnection) {
            ForEach(outConnections) { Text($0.rawValue).tag($0) }
        }
        if outputConnection.wrappedValue == .custom || outputConnection.wrappedValue == .special {
            TextField("Custom outlet connection", text: $fitting.outletSpecial)
                .focused($dimensionFocused)
        }
    }
    if isTee {
        Picker("Right (E × F)", selection: teeRightConnection) {
            ForEach(FabConnection.rectangular) { Text($0.rawValue).tag($0) }
        }
        if teeRightConnection.wrappedValue == .custom || teeRightConnection.wrappedValue == .special {
            TextField("Custom right connection", text: teeRightSpecial)
                .focused($dimensionFocused)
        }
    }
    if fitting.shape == .squareRound || fitting.shape.isHeto {
        Toggle("Include damper", isOn: damper)
    }
}
    }
    @ViewBuilder
    private var materialAndGauge: some View {
        Section("Material & Gauge") {
            Toggle("Override area material", isOn: Binding(
                get: { fitting.materialOverride != nil },
                set: { useOverride in
                    fitting.materialOverride = useOverride ? fitting.effectiveMaterial(in: area) : nil
                }
            ))
            Picker("Material", selection: materialSelection) {
                ForEach(FabMaterial.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(fitting.materialOverride == nil && area != nil)
            Toggle("Override area gauge", isOn: Binding(
                get: { fitting.gaugeOverride != nil },
                set: { useOverride in
                    if useOverride {
                        let current = fitting.effectiveGauge(in: area)
                        fitting.gaugeOverride = current
                        if current == .custom { fitting.customGaugeOverride = area?.customGauge }
                    } else {
                        fitting.gaugeOverride = nil
                        fitting.customGaugeOverride = nil
                    }
                }
            ))
            Picker("Gauge", selection: gaugeSelection) {
                ForEach(FabGauge.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(fitting.gaugeOverride == nil && area != nil)
            if fitting.effectiveGauge(in: area) == .custom {
                TextField("Custom gauge or thickness", text: customGaugeText)
                    .focused($dimensionFocused)
                    .disabled(fitting.gaugeOverride == nil && area != nil)
            }
            Text("Effective: \(fitting.effectiveMaterial(in: area).rawValue) · \(fitting.effectiveGaugeLabel(in: area))")
                .font(.caption).foregroundColor(.secondary)
        }
    }
    var body: some View {
        Form {
            Section("Fitting") {
                Text(fitting.shape.displayName).font(.headline)
                TextField("Fitting label (optional)", text: $fitting.name)
                    .focused($dimensionFocused)
                Stepper("Quantity: \(fitting.quantity)", value: $fitting.quantity, in: 1...9999)
            }
            if !fitting.shape.isCustom {
                Section("Fitting Diagram · Dimension Letters") {
                    if fitting.shape.isCatalogRect || fitting.shape.isCatalogRound {
                        FabDiagramView(fitting: fitting, compact: false)
                            .frame(maxWidth: .infinity)
                    } else {
                        FabFittingGlyph(shape: fitting.shape)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                    }
                    Text(fitting.dimensionLegend)
                        .font(.caption).foregroundColor(.secondary)
                    Button {
                        dimensionFocused = false
                        show3DPreview = true
                    } label: {
                        Label("View 3D", systemImage: "cube.transparent")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                }
                measurementsAndAlignment
                connectorSection
                if isRound {
                    Section("Round Insulation") {
                        Toggle("Use area insulation type", isOn: Binding(
                            get: { fitting.roundInsulationOverride == nil },
                            set: { fitting.roundInsulationOverride = $0 ? nil : fitting.effectiveRoundInsulation(in: area) }
                        ))
                        Picker("Insulation type", selection: Binding(
                            get: { fitting.effectiveRoundInsulation(in: area) },
                            set: { fitting.roundInsulationOverride = $0 }
                        )) {
                            ForEach(FabRoundInsulation.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .disabled(fitting.roundInsulationOverride == nil && area != nil)
                        if fitting.effectiveRoundInsulation(in: area) != .none {
                            Toggle("Use area thickness", isOn: Binding(
                                get: { fitting.roundThicknessOverride == nil },
                                set: { fitting.roundThicknessOverride = $0 ? nil : fitting.effectiveRoundThickness(in: area) }
                            ))
                            Picker("Insulation thickness", selection: Binding(
                                get: { fitting.effectiveRoundThickness(in: area) },
                                set: { fitting.roundThicknessOverride = $0 }
                            )) {
                                ForEach(FabThickness.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .disabled(fitting.roundThicknessOverride == nil && area != nil)
                        }
                        Text("Defaults can be overridden independently for type and thickness.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Section("Rectangular Liner") {
                        Toggle("Use area liner default", isOn: Binding(
                            get: { fitting.linerOverride == nil },
                            set: { fitting.linerOverride = $0 ? nil : fitting.effectiveLiner(in: area) }
                        ))
                        Picker("Liner", selection: Binding(
                            get: { fitting.effectiveLiner(in: area) },
                            set: { fitting.linerOverride = $0 }
                        )) {
                            ForEach(FabLiner.allCases) { Text($0.rawValue).tag($0) }
                        }.disabled(fitting.linerOverride == nil && area != nil)
                    }
                }
            }
            materialAndGauge
            Section(fitting.shape.isCustom ? "Describe Custom Fitting (Required)" : "Shop Notes") {
                TextEditor(text: $fitting.notes)
                    .focused($dimensionFocused)
                    .frame(minHeight: 78)
            }
            Section {
                Text("Dimensions are finished inches; liner and insulation never automatically change the entered measurements. Drawings are labeled schematics, not flat patterns.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .navigationTitle("Fitting Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { dimensionFocused = false } label: {
                    Label("Hide Keyboard", systemImage: "chevron.down")
                }
                Button("Done") { dimensionFocused = false }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if fitting.validationMessage != nil { showError = true }
                    else {
                        onSave(fitting)
                        if dismissAfterSave { dismiss() }
                    }
                }
            }
        }
        .alert("Check Measurements", isPresented: $showError) {
            Button("OK") {}
        } message: { Text(fitting.validationMessage ?? "Please check your fitting.") }
        .sheet(isPresented: $show3DPreview) {
            FabReadOnly3DPreview(fitting: fitting)
        }
    }
}

// The original FieldFab SceneKit engine already constructs dimension-driven
// rectangular walls. Adapt only fitting types it can represent correctly.
// Other fitting types intentionally display an honest unsupported message
// until their dedicated mesh generators are implemented.
private struct FabReadOnly3DPreview: View {
    @Environment(\.dismiss) private var dismiss
    let fitting: FabFitting

    private var legacyDuct: DuctTransition.DuctData? {
        guard fitting.shape == .rectStraight || fitting.shape == .rectTransition else { return nil }
        guard fitting.inletWidth > 0, fitting.inletHeight > 0, fitting.length > 0 else { return nil }
        var duct = DuctTransition.DuctData()
        duct.name = fitting.name.isEmpty ? fitting.shape.displayName : fitting.name
        duct.isTransition = fitting.shape == .rectTransition
        duct.unit = .inch
        duct.measurements = [
            fitting.inletWidth, fitting.inletHeight, fitting.length,
            fitting.shape == .rectTransition ? fitting.offsetX : 0,
            fitting.shape == .rectTransition ? fitting.offsetY : 0,
            fitting.shape == .rectTransition ? fitting.outletWidth : fitting.inletWidth,
            fitting.shape == .rectTransition ? fitting.outletHeight : fitting.inletHeight
        ]
        return duct
    }

    var body: some View {
        NavigationStack {
            Group {
                if let duct = legacyDuct {
                    GeometryReader { geo in
                        DuctTransition.SceneView(
                            geo: geo,
                            textShown: false,
                            ductwork: duct,
                            ductSceneHitTest: { _ in },
                            selectorShown: .constant(false)
                        )
                    }
                    .overlay(alignment: .bottom) {
                        Text("Read-only preview · Drag to rotate · Pinch to zoom")
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.bottom, 16)
                    }
                } else {
                    ContentUnavailableView(
                        "3D Preview Not Yet Available",
                        systemImage: "cube.transparent",
                        description: Text("The 3D mesh generator for \(fitting.shape.displayName) has not been added yet. Your fitting dimensions and 2D drawing are unaffected.")
                    )
                }
            }
            .navigationTitle("3D · \(fitting.shape.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// Shared image source for both the iPhone editor and exported PDF.
struct FabDiagramView: View {
    let fitting: FabFitting
    let compact: Bool
    var body: some View {
        let images = FabDiagramArt.images(for: fitting)
        Group {
            if images.isEmpty {
                Text("Drawing asset missing — check Fab*.imageset files")
                    .font(.caption).foregroundColor(.red)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(images.indices, id: \.self) { index in
                        Image(uiImage: images[index])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 86 : (images.count > 1 ? 160 : 185))
                            .accessibilityLabel(Text(fitting.shape.displayName + " reference drawing"))
                    }
                }
                .padding(3)
                .background(Color.white)
            }
        }
    }
}

// Compact, recognizable thumbnail for each saved fitting in an area list.
// The same CAD artwork used in the fitting selector and fabrication PDF is reused here.
// Use the actual fitting to respect reducer alignment and other image-specific options.
struct FabFittingListIcon: View {
    let fitting: FabFitting

    private var drawing: UIImage? {
        guard fitting.shape.isCatalogRect || fitting.shape.isCatalogRound else { return nil }
        return FabDiagramArt.images(for: fitting).first
    }

    var body: some View {
        Group {
            if let drawing = drawing {
                Image(uiImage: drawing)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
            } else {
                FabLegacyGlyph(shape: fitting.shape)
                    .padding(3)
            }
        }
        .accessibilityHidden(true)
    }
}

struct FabFittingGlyph: View {
    let shape: FabShape
    var body: some View {
        Group {
            if shape.isCatalogRect || shape.isCatalogRound {
                FabDiagramView(fitting: .new(shape: shape, areaID: nil), compact: true)
            } else {
                FabLegacyGlyph(shape: shape)
            }
        }
    }
}

// Original schematic artwork is retained for round and legacy fitting types.
// A/B and C/D stay consistent from the icon through the PDF and input form.
struct FabLegacyGlyph: View {
    let shape: FabShape
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x / 100, y: h * y / 100) }
            var outline = Path()
            func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
                outline.move(to: point(a.0, a.1)); outline.addLine(to: point(b.0, b.1))
            }
            func label(_ title: String, _ x: CGFloat, _ y: CGFloat) {
                context.draw(Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary),
                             at: point(x, y))
            }
            switch shape {
            case .rectStraight, .roundStraight, .roundSpiral:
                outline.addRect(CGRect(x: w*0.20, y: h*0.32, width: w*0.60, height: h*0.36))
                if shape.isRound {
                    outline.addEllipse(in: CGRect(x: w*0.18, y: h*0.32, width: w*0.10, height: h*0.36))
                    outline.addEllipse(in: CGRect(x: w*0.74, y: h*0.32, width: w*0.10, height: h*0.36))
                }
            case .rectTransition, .squareRound, .roundReducer, .roundEccentric, .roundHeto90, .roundHeto45:
                line((17,27),(32,27)); line((32,27),(67,37)); line((67,37),(82,37))
                line((17,73),(32,73)); line((32,73),(67,63)); line((67,63),(82,63))
                line((17,27),(17,73)); line((82,37),(82,63))
                if shape.isRound {
                    outline.addEllipse(in: CGRect(x:w*0.14,y:h*0.27,width:w*0.075,height:h*0.46))
                    outline.addEllipse(in: CGRect(x:w*0.78,y:h*0.37,width:w*0.075,height:h*0.26))
                }
            case .rectOffset, .roundOffset:
                line((13,31),(33,31)); line((33,31),(65,45)); line((65,45),(87,45))
                line((13,58),(33,58)); line((33,58),(65,72)); line((65,72),(87,72))
                line((13,31),(13,58)); line((87,45),(87,72))
            case .rectElbow90, .rectElbow45:
                if shape == .rectElbow90 {
                    line((18,81),(18,19)); line((18,19),(80,19)); line((80,19),(80,81))
                    line((18,81),(80,81))
                    for i in 0..<5 {
                        let x = CGFloat(28 + i*10)
                        outline.move(to: point(x, 77 - CGFloat(i)*10))
                        outline.addQuadCurve(to: point(x+13, 79 - CGFloat(i)*10), control: point(x+1, 92 - CGFloat(i)*10))
                    }
                } else {
                    outline.move(to: point(18,80)); outline.addLine(to: point(18,46))
                    outline.addLine(to: point(54,12)); outline.addLine(to: point(84,44))
                    outline.addLine(to: point(60,66)); outline.addLine(to: point(78,80)); outline.closeSubpath()
                }
            case .roundElbow45, .roundElbow90:
                let high: CGFloat = shape == .roundElbow45 ? 30 : 15
                outline.move(to: point(12,79)); outline.addLine(to: point(38,79))
                outline.addQuadCurve(to: point(80,high), control: point(80,79))
                outline.move(to: point(12,60)); outline.addLine(to: point(38,60))
                outline.addQuadCurve(to: point(61,high), control: point(61,60))
            case .roundTee:
                line((12,40),(88,40)); line((12,64),(88,64))
                line((12,40),(12,64)); line((88,40),(88,64))
                line((43,40),(43,14)); line((63,40),(63,14)); line((43,14),(63,14))
            case .rectRadiusElbow, .rectTee, .rectEndCap, .roundEndCap:
                outline.addRect(CGRect(x: w*0.20, y: h*0.20, width: w*0.60, height: h*0.60))
            case .custom:
                outline.addRect(CGRect(x:w*0.20,y:h*0.20,width:w*0.60,height:h*0.60))
            }
            context.stroke(outline, with: .color(.primary), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            if shape.isCustom {
                label("?",50,50)
            } else if shape.isRoundElbow {
                label("A",8,54); label("C",85,14); label("J",53,48)
            } else if shape.isRectElbow {
                label("A",8,77); label("B",22,91); label("C",83,15); label("D",92,36)
                label("K",37,9); label("L",91,73)
            } else {
                label("A",9,38)
                if !shape.isRound { label("B",9,64) }
                label("C",92,40)
                if !shape.isRound && shape != .squareRound { label("D",92,64) }
                if shape.isTransition {
                    label("E",48,91)
                    label("F",48,16)
                    label("G",68,82)
                } else if shape.isStraight {
                    label("E",50,86)
                }
            }
        }
        .accessibilityLabel(Text(shape.displayName + " dimension key illustration"))
    }
}

struct FabShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FabExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
