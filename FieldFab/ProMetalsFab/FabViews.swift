import SwiftUI
import UIKit
import SceneKit

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
    private var reducerInletCollarSelection: Binding<FabHetoLengthMode> {
        Binding(get: { fitting.reducerInletMode }, set: {
            fitting.reducerInletCollarMode = $0
            fitting.syncReducerOverallLength()
        })
    }
    private var reducerOutletCollarSelection: Binding<FabHetoLengthMode> {
        Binding(get: { fitting.reducerOutletMode }, set: {
            fitting.reducerOutletCollarMode = $0
            fitting.syncReducerOverallLength()
        })
    }
    private var reducerInletCustomLength: Binding<Double> {
        Binding(get: { fitting.reducerInletCollarCustomLength ?? 4 }, set: {
            fitting.reducerInletCollarCustomLength = $0
            fitting.syncReducerOverallLength()
        })
    }
    private var reducerOutletCustomLength: Binding<Double> {
        Binding(get: { fitting.reducerOutletCollarCustomLength ?? 4 }, set: {
            fitting.reducerOutletCollarCustomLength = $0
            fitting.syncReducerOverallLength()
        })
    }
    private var reducerCenterBodyLength: Binding<Double> {
        Binding(get: { fitting.effectiveReducerBodyLength }, set: {
            fitting.reducerBodyLength = $0
            fitting.syncReducerOverallLength()
        })
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
    private var turningVanes: Binding<Bool> {
        Binding(get: { fitting.hasTurningVanes },
                set: { fitting.showTurningVanes = $0 })
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
            Picker("Inlet Collar Length", selection: reducerInletCollarSelection) {
                Text("Standard — 4″").tag(FabHetoLengthMode.standard)
                Text("Custom").tag(FabHetoLengthMode.custom)
            }
            if fitting.reducerInletMode == .custom {
                number("Inlet Collar — Custom Length", reducerInletCustomLength)
            }
            Picker("Outlet Collar Length", selection: reducerOutletCollarSelection) {
                Text("Standard — 4″").tag(FabHetoLengthMode.standard)
                Text("Custom").tag(FabHetoLengthMode.custom)
            }
            if fitting.reducerOutletMode == .custom {
                number("Outlet Collar — Custom Length", reducerOutletCustomLength)
            }
            number("Center Body Length", reducerCenterBodyLength)
            HStack {
                Text("C — Overall Length")
                Spacer()
                Text(fabInches(fitting.reducerOverallLength))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Text("Overall = inlet collar + center body + outlet collar.")
                .font(.caption)
                .foregroundColor(.secondary)
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
            Picker("Turning Vanes", selection: turningVanes) {
                Text("Vanes").tag(true)
                Text("No Vanes").tag(false)
            }
        } else {
            number("C — Width Out", $fitting.outletWidth)
            number("D — Depth Out", $fitting.outletHeight)
            if isSquareElbow {
                number("E — Throat Length 1", $fitting.straightIn)
                number("F — Throat Length 2", $fitting.straightOut)
                Picker("Turning Vanes", selection: turningVanes) {
                    Text("Vanes").tag(true)
                    Text("No Vanes").tag(false)
                }
            } else if fitting.shape == .rectRadiusElbow {
                Picker("Turning Vanes", selection: turningVanes) {
                    Text("Vanes").tag(true)
                    Text("No Vanes").tag(false)
                }
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
    @State private var previewAction = 0
    @State private var previewActionID = 0
    @State private var showDimensions = true

    private func control(_ action: Int) {
        previewAction = action
        previewActionID += 1
    }

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
                if FabFittingScenePreview.isSupported(fitting.shape) {
                    GeometryReader { _ in
                        FabFittingScenePreview(fitting: fitting,
                                             showDimensions: showDimensions,
                                             resetID: previewActionID)
                    }
                    .overlay(alignment: .topTrailing) {
                        Toggle("Dimensions", isOn: $showDimensions)
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(12)
                    }
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 10) {
                            Button { control(3) } label: {
                                Label("Reset View", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            Text("Read-only · Drag to orbit · Pinch to zoom")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 12)
                    }
                } else if let duct = legacyDuct {
                    GeometryReader { geo in
                        DuctTransition.SceneView(
                            geo: geo,
                            textShown: false,
                            ductwork: duct,
                            ductSceneHitTest: { _ in },
                            selectorShown: .constant(false),
                            isFabPreview: true,
                            previewAction: previewAction,
                            previewActionID: previewActionID,
                            showFabLabels: showDimensions
                        )
                    }
                    .overlay(alignment: .topTrailing) {
                        Toggle("Dimensions", isOn: $showDimensions)
                            .toggleStyle(.switch)
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(12)
                    }
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 10) {
                            Button { control(3) } label: {
                                Label("Reset View", systemImage: "arrow.counterclockwise")
                            }
                            .accessibilityLabel("Reset 3D view")
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .font(.headline)
                            Text("Read-only · Drag to orbit · Pinch to zoom")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("3D Preview Not Yet Available")
                            .font(.headline)
                        Text("The 3D mesh generator for \(fitting.shape.displayName) has not been added yet. Your fitting dimensions and 2D drawing are unaffected.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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


 // MARK: - ProMetalsFab dimension-driven, read-only fitting SceneKit previews.
 // Dimensions are inches in the fitting model; rendering uses meters.
 private struct FabFittingScenePreview: UIViewRepresentable {
     let fitting: FabFitting
     let showDimensions: Bool
     let resetID: Int

     static func isSupported(_ shape: FabShape) -> Bool {
         switch shape {
         case .roundSpiral, .roundStraight, .roundReducer, .roundEccentric,
              .roundEndCap, .roundElbow45, .roundElbow90, .squareRound,
              .roundHeto90, .roundHeto45, .rectEndCap, .rectElbow45,
              .rectElbow90, .rectRadiusElbow, .rectTee: return true
         default: return false
         }
     }

     final class PreviewSceneView: SCNView {
         var priorResetID = 0
         var priorLabels = true
         var initialCameraPosition = SCNVector3Zero
         var initialCameraTarget = SCNVector3Zero
     }

     func makeUIView(context: Context) -> PreviewSceneView {
         let view = PreviewSceneView(frame: .zero)
         view.allowsCameraControl = true
         view.autoenablesDefaultLighting = true
         view.backgroundColor = UIColor.secondarySystemBackground
         view.antialiasingMode = .multisampling4X
         view.scene = buildScene()
         view.priorResetID = resetID
         view.priorLabels = showDimensions
         focusCamera(view)
         return view
     }

     func updateUIView(_ view: PreviewSceneView, context: Context) {
         if view.priorLabels != showDimensions {
             view.priorLabels = showDimensions
             view.scene?.rootNode.enumerateChildNodes { node, _ in
                 if node.name == "roundDimensionLabel" {
                     node.isHidden = !showDimensions
                 }
             }
         }
         if view.priorResetID != resetID {
             view.priorResetID = resetID
             focusCamera(view)
         }
     }

     private func focusCamera(_ view: PreviewSceneView) {
         guard let scene = view.scene,
               let body = scene.rootNode.childNode(withName: "fitting", recursively: false) else { return }
         let (low, high) = body.boundingBox
         let center = SCNVector3((low.x + high.x)/2, (low.y + high.y)/2, (low.z + high.z)/2)
         let x = high.x-low.x, y = high.y-low.y, z = high.z-low.z
         let span = max(sqrt(x*x+y*y+z*z), 0.2)
         let camera = SCNNode()
         camera.camera = SCNCamera()
         camera.camera?.zNear = 0.005
         camera.camera?.zFar = 500
         camera.position = SCNVector3(center.x + span * 1.25, center.y + span * 0.85, center.z + span * 1.75)
         camera.look(at: center)
         scene.rootNode.childNode(withName: "previewCamera", recursively: false)?.removeFromParentNode()
         camera.name = "previewCamera"
         scene.rootNode.addChildNode(camera)
         view.pointOfView = camera
         view.initialCameraPosition = camera.position
         view.initialCameraTarget = center
     }

     private var toMeters: CGFloat { 0.0254 }
     private func m(_ inches: Double) -> CGFloat { CGFloat(inches) * toMeters }
     private func dimension(_ inches: Double) -> String {
         String(format: "%g", inches) + "\u{2033}"
     }
     private var metal: SCNMaterial {
         let material = SCNMaterial()
         // Match the galvanized finish used by the rectangular 3D engine.
         material.diffuse.contents = UIImage(named: "galvanized-diffuse")
             ?? UIColor(red: 0.71, green: 0.75, blue: 0.79, alpha: 1)
         material.metalness.contents = UIImage(named: "galvanized-metallic") ?? 0.5
         material.normal.contents = UIImage(named: "galvanized-normal")
         material.roughness.contents = UIImage(named: "galvanized-roughness") ?? 0.42
         material.lightingModel = .physicallyBased
         material.isDoubleSided = true
         return material
     }

     private func addLabel(_ text: String, at position: SCNVector3, to root: SCNNode, scale: Float) {
         let geometry = SCNText(string: text, extrusionDepth: 0)
         geometry.font = UIFont.boldSystemFont(ofSize: 1)
         geometry.flatness = 0.08
         let mat = SCNMaterial()
         mat.diffuse.contents = UIColor.systemYellow
         mat.lightingModel = .constant
         mat.isDoubleSided = true
         geometry.materials = [mat]
         let node = SCNNode(geometry: geometry)
         node.name = "roundDimensionLabel"
         node.isHidden = !showDimensions
         let (low, high) = geometry.boundingBox
         node.pivot = SCNMatrix4MakeTranslation((low.x + high.x)/2, (low.y + high.y)/2, 0)
         node.scale = SCNVector3(scale, scale, scale)
         node.position = position
         node.constraints = [SCNBillboardConstraint()]
         // Labels do not affect framing, but orbit with the model.
         if let parent = root.parent {
             parent.addChildNode(node)
         } else {
             root.addChildNode(node)
         }
     }

     private func mesh(rings: [[SCNVector3]], closeStart: Bool = false,
                       closeEnd: Bool = false) -> SCNGeometry {
         let count = rings[0].count
         let points = rings.flatMap { $0 }
         var indices: [UInt32] = []
         if rings.count >= 2 {
             for row in 0..<(rings.count - 1) {
                 for col in 0..<count {
                     let next = (col + 1) % count
                     let a = UInt32(row * count + col)
                     let b = UInt32(row * count + next)
                     let c = UInt32((row + 1) * count + col)
                     let d = UInt32((row + 1) * count + next)
                     indices.append(contentsOf: [a,c,b,b,c,d])
                 }
             }
         }
         var vertices = points
         if closeStart {
             let center = average(rings[0])
             let idx = UInt32(vertices.count)
             vertices.append(center)
             for col in 0..<count {
                 indices.append(contentsOf: [idx, UInt32((col+1)%count), UInt32(col)])
             }
         }
         if closeEnd {
             let center = average(rings[rings.count-1])
             let idx = UInt32(vertices.count)
             vertices.append(center)
             let base = UInt32((rings.count-1)*count)
             for col in 0..<count {
                 indices.append(contentsOf: [idx,base+UInt32(col),base+UInt32((col+1)%count)])
             }
         }
         // Smooth explicit vertex normals eliminate visible triangulation
         // artifacts without drawing break or segment lines on the shell.
         var normals: [SCNVector3] = []
         var texcoords: [CGPoint] = []
         for row in 0..<rings.count {
             for col in 0..<count {
                 let prev = rings[row][(col + count - 1) % count]
                 let next = rings[row][(col + 1) % count]
                 let lower = rings[max(0, row - 1)][col]
                 let upper = rings[min(rings.count - 1, row + 1)][col]
                 let ux = next.x - prev.x, uy = next.y - prev.y, uz = next.z - prev.z
                 let vx = upper.x - lower.x, vy = upper.y - lower.y, vz = upper.z - lower.z
                 let nx = vy * uz - vz * uy
                 let ny = vz * ux - vx * uz
                 let nz = vx * uy - vy * ux
                 let mag = max(sqrt(nx * nx + ny * ny + nz * nz), Float(0.00001))
                 normals.append(SCNVector3(nx / mag, ny / mag, nz / mag))
                 texcoords.append(CGPoint(x: CGFloat(col) / CGFloat(count),
                                        y: CGFloat(row) / CGFloat(max(1, rings.count - 1))))
             }
         }
         if closeStart {
             normals.append(SCNVector3(0, -1, 0))
             texcoords.append(CGPoint(x: 0.5, y: 0))
         }
         if closeEnd {
             normals.append(SCNVector3(0, 1, 0))
             texcoords.append(CGPoint(x: 0.5, y: 1))
         }
         let vData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
         let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
         let source = SCNGeometrySource(data: vData, semantic: .vertex,
                                       vectorCount: vertices.count,
                                       usesFloatComponents: true,
                                       componentsPerVector: 3,
                                       bytesPerComponent: MemoryLayout<Float>.size,
                                       dataOffset: 0,
                                       dataStride: MemoryLayout<SCNVector3>.stride)
         let element = SCNGeometryElement(data: iData, primitiveType: .triangles,
                                          primitiveCount: indices.count/3,
                                          bytesPerIndex: MemoryLayout<UInt32>.size)
         let geo = SCNGeometry(sources: [source,
                                         SCNGeometrySource(normals: normals),
                                         SCNGeometrySource(textureCoordinates: texcoords)],
                               elements: [element])
         geo.materials = [metal]
         return geo
     }
     private func average(_ points: [SCNVector3]) -> SCNVector3 {
         let n = Float(points.count)
         return SCNVector3(points.reduce(Float(0)) { $0+$1.x }/n,
                           points.reduce(Float(0)) { $0+$1.y }/n,
                           points.reduce(Float(0)) { $0+$1.z }/n)
     }
     private func circularRing(radius: Float, y: Float, shiftX: Float = 0,
                               shiftZ: Float = 0, sides: Int = 64) -> [SCNVector3] {
         (0..<sides).map { index in
             let angle = Float(index)*2*Float.pi/Float(sides)
             return SCNVector3(shiftX+radius*cos(angle), y, shiftZ+radius*sin(angle))
         }
     }

     // Explicitly sample each rectangular corner. Both rims use IDENTICAL
     // angular stations so A x B is exact, C stays circular, and the loft
     // does not introduce a twist or round off the rectangular corners.
     private func squareRoundAngles(halfWidth: Float, halfDepth: Float) -> [Float] {
         let corner = atan2(halfDepth, halfWidth)
         let quarter = Float.pi / 2
         var angles: [Float] = []
         for quadrant in 0..<4 {
             let base = Float(quadrant) * quarter
             // A non-square rectangle has alternating corner angles.
             let quadrantCorner = quadrant % 2 == 0 ? corner : quarter - corner
             for segment in 0..<16 {
                 let t = Float(segment)
                 let local = segment < 8
                     ? quadrantCorner * t / 8
                     : quadrantCorner + (quarter - quadrantCorner) * (t - 8) / 8
                 angles.append(base + local)
             }
         }
         return angles
     }

     private func squareRoundRings(halfWidth: Float, halfDepth: Float,
                                   outletRadius: Float, length: Float) -> [[SCNVector3]] {
         let angles = squareRoundAngles(halfWidth: halfWidth, halfDepth: halfDepth)
         let rectangle = angles.map { angle -> SCNVector3 in
             let dx = cos(angle), dz = sin(angle)
             let tx = abs(dx) > 0.00001 ? halfWidth / abs(dx) : Float.greatestFiniteMagnitude
             let tz = abs(dz) > 0.00001 ? halfDepth / abs(dz) : Float.greatestFiniteMagnitude
             let distance = min(tx, tz)
             return SCNVector3(distance * dx, -length / 2, distance * dz)
         }
         let circle = angles.map { angle in
             SCNVector3(outletRadius * cos(angle), length / 2,
                        outletRadius * sin(angle))
         }
         return [rectangle, circle]
     }

     // Four real corners for rectangular duct ends; no cosmetic crease lines.
     private func rectangularEnd(width: Float, depth: Float, y: Float) -> [SCNVector3] {
         let w = max(width, 0.001) / 2
         let d = max(depth, 0.001) / 2
         return [SCNVector3(w, y, d), SCNVector3(-w, y, d),
                 SCNVector3(-w, y, -d), SCNVector3(w, y, -d)]
     }

     // A cross-section normal to a bend travelling in the XY plane.
     private func bentRectangle(x: Float, y: Float, angle: Float,
                                width: Float, depth: Float,
                                zShift: Float = 0) -> [SCNVector3] {
         let w = max(width, 0.001) / 2
         let d = max(depth, 0.001) / 2
         let c = cos(angle), si = sin(angle)
         return [(w,d),(-w,d),(-w,-d),(w,-d)].map { corner in
             SCNVector3(x + corner.0 * c, y - corner.0 * si,
                        zShift + corner.1)
         }
     }

     // Rectangular branch sleeve whose length runs along the X axis.
     private func branchEnd(x: Float, width: Float, depth: Float,
                            centerY: Float = 0) -> [SCNVector3] {
         let w = max(width, 0.001) / 2
         let d = max(depth, 0.001) / 2
         return [SCNVector3(x, centerY+w, d), SCNVector3(x, centerY-w, d),
                 SCNVector3(x, centerY-w, -d), SCNVector3(x, centerY+w, -d)]
     }

     // High-efficiency takeoff: an open rectangular mounting mouth lofts to
     // an open circular mouth while its centerline turns through 45 or 90 deg.
     // This is a visual guide, not a developed cut-pattern calculation.
     private func hetoRings(rectWidth: Float, rectDepth: Float,
                            roundRadius: Float, centerlineLength: Float,
                            radians: Float) -> [[SCNVector3]] {
         let w = max(rectWidth, 0.001) / 2
         let d = max(rectDepth, 0.001) / 2
         let angles = squareRoundAngles(halfWidth: w, halfDepth: d)
         let bendRadius = centerlineLength / max(radians, 0.01)
         let sections = 20
         return (0...sections).map { step -> [SCNVector3] in
             let t = Float(step) / Float(sections)
             let theta = radians * t
             let cx = bendRadius * (1 - cos(theta))
             let cy = bendRadius * sin(theta)
             return angles.map { phi in
                 let dx = cos(phi), dz = sin(phi)
                 let tx = abs(dx) > 0.00001 ? w / abs(dx) : Float.greatestFiniteMagnitude
                 let tz = abs(dz) > 0.00001 ? d / abs(dz) : Float.greatestFiniteMagnitude
                 let r = min(tx, tz)
                 let across = (1 - t) * r * dx + t * roundRadius * dx
                 let alongDepth = (1 - t) * r * dz + t * roundRadius * dz
                 return SCNVector3(cx + across * cos(theta),
                                   cy - across * sin(theta), alongDepth)
             }
         }
     }

     // The tee is assembled from three open rectangular sleeves. The central
     // overlap is illustrative; throat sizes control each outlet and reach.
     private func addTee(to body: SCNNode, labelOffset: Float,
                         labelSize: Float) {
         let a = max(Float(m(fitting.inletWidth)), 0.001)
         let b = max(Float(m(fitting.inletHeight)), 0.001)
         let c = max(Float(m(fitting.outletWidth)), 0.001)
         let d = max(Float(m(fitting.outletHeight)), 0.001)
         let e = max(Float(m(fitting.teeE)), 0.001)
         let f = max(Float(m(fitting.teeF)), 0.001)
         let trunk = max(Float(m(8)), a * 0.6)
         let left = max(Float(m(6)), Float(m(fitting.teeG + fitting.teeH)) + c * 0.35)
         let right = max(Float(m(6)), Float(m(fitting.teeI + fitting.teeJ)) + e * 0.35)
         body.addChildNode(SCNNode(geometry: mesh(rings: [
             rectangularEnd(width: a, depth: b, y: -trunk),
             rectangularEnd(width: a, depth: b, y: 0)
         ])))
         body.addChildNode(SCNNode(geometry: mesh(rings: [
             branchEnd(x: -left, width: c, depth: d),
             branchEnd(x: 0, width: c, depth: d)
         ])))
         body.addChildNode(SCNNode(geometry: mesh(rings: [
             branchEnd(x: 0, width: e, depth: f),
             branchEnd(x: right, width: e, depth: f)
         ])))
         addLabel("A  " + dimension(fitting.inletWidth),
                  at: SCNVector3(0, -trunk, b / 2 + labelOffset/2),
                  to: body, scale: labelSize)
         addLabel("B  " + dimension(fitting.inletHeight),
                  at: SCNVector3(a/2 + labelOffset/2, -trunk, 0),
                  to: body, scale: labelSize)
         addLabel("C  " + dimension(fitting.outletWidth),
                  at: SCNVector3(-left, c/2 + labelOffset/2, 0),
                  to: body, scale: labelSize)
         addLabel("D  " + dimension(fitting.outletHeight),
                  at: SCNVector3(-left, 0, d/2 + labelOffset/2),
                  to: body, scale: labelSize)
         addLabel("E  " + dimension(fitting.teeE),
                  at: SCNVector3(right, e/2 + labelOffset/2, 0),
                  to: body, scale: labelSize)
         addLabel("F  " + dimension(fitting.teeF),
                  at: SCNVector3(right, 0, f/2 + labelOffset/2),
                  to: body, scale: labelSize)
         addLabel("G  " + dimension(fitting.teeG),
                  at: SCNVector3(-left * 0.45, c/2 + labelOffset, -d/2),
                  to: body, scale: labelSize * 0.8)
         addLabel("H  " + dimension(fitting.teeH),
                  at: SCNVector3(-left * 0.45, -c/2 - labelOffset, -d/2),
                  to: body, scale: labelSize * 0.8)
         addLabel("I  " + dimension(fitting.teeI),
                  at: SCNVector3(right * 0.45, -e/2 - labelOffset, -f/2),
                  to: body, scale: labelSize * 0.8)
         addLabel("J  " + dimension(fitting.teeJ),
                  at: SCNVector3(right * 0.45, e/2 + labelOffset, -f/2),
                  to: body, scale: labelSize * 0.8)
     }

     private func buildScene() -> SCNScene {
         let scene = SCNScene()
         let body = SCNNode()
         body.name = "fitting"
         scene.rootNode.addChildNode(body)
         let diameter = max(Float(m(fitting.inletWidth)), 0.001)
         let radius = diameter/2
         let labelOffset = max(diameter*0.75, 0.075)
         let labelSize = max(diameter*0.15, 0.013)
         switch fitting.shape {
         case .roundStraight, .roundSpiral:
             let length = max(Float(m(fitting.length)), 0.001)
             let geo = mesh(rings: [circularRing(radius: radius, y: -length/2),
                                    circularRing(radius: radius, y: length/2)])
             body.addChildNode(SCNNode(geometry: geo))
             addLabel("A  " + dimension(fitting.length), at: SCNVector3(radius+labelOffset, 0, 0), to: body, scale: labelSize)
             addLabel("B  " + dimension(fitting.inletWidth), at: SCNVector3(0, -length/2, radius+labelOffset/2), to: body, scale: labelSize)
         case .squareRound:
             // Matched contour stations give an untwisted open square-to-round loft.
             let length = max(Float(m(fitting.length)), 0.001)
             let halfWidth = max(Float(m(fitting.inletWidth)) / 2, 0.0005)
             let halfDepth = max(Float(m(fitting.inletHeight)) / 2, 0.0005)
             let outletRadius = max(Float(m(fitting.outletWidth)) / 2, 0.0005)
             let rings = squareRoundRings(halfWidth: halfWidth, halfDepth: halfDepth,
                                         outletRadius: outletRadius, length: length)
             body.addChildNode(SCNNode(geometry: mesh(rings: rings)))
             let reach = max(halfWidth, halfDepth, outletRadius)
             addLabel("A  " + dimension(fitting.inletWidth),
                      at: SCNVector3(0, -length/2, halfDepth + labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("B  " + dimension(fitting.inletHeight),
                      at: SCNVector3(halfWidth + labelOffset/2, -length/2, 0),
                      to: body, scale: labelSize)
             addLabel("C  Ø " + dimension(fitting.outletWidth),
                      at: SCNVector3(0, length/2, outletRadius + labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("D  " + dimension(fitting.length),
                      at: SCNVector3(reach + labelOffset, 0, 0),
                      to: body, scale: labelSize)
         case .roundHeto90, .roundHeto45:
             // The rectangular opening is the mounting mouth. The round
             // outlet turns through 90 or 45 degrees relative to that mouth.
             let a = max(Float(m(fitting.inletWidth)), 0.001)
             let b = max(Float(m(fitting.inletHeight)), 0.001)
             let c = max(Float(m(fitting.outletWidth)), 0.001)
             let outletRadius = c/2
             let turn = fitting.shape == .roundHeto90 ? Float.pi/2 : Float.pi/4
             // "Standard" is a fitting-shop sizing mode, not an explicit
             // entered dimension; use a proportional illustrative length.
             let standardLength = max(a, max(b, c)) * 1.1
             let centerlineLength = fitting.hetoMode == .custom
                 ? max(Float(m(fitting.length)), 0.001) : standardLength
             let rings = hetoRings(rectWidth: a, rectDepth: b,
                                   roundRadius: outletRadius,
                                   centerlineLength: centerlineLength,
                                   radians: turn)
             body.addChildNode(SCNNode(geometry: mesh(rings: rings)))
             let centerRadius = centerlineLength / turn
             let exitX = centerRadius * (1 - cos(turn))
             let exitY = centerRadius * sin(turn)
             if fitting.isDampered {
                 // A thin blade inside the round outlet indicates the selected
                 // damper; shafts, seals, and specific hardware are intentionally
                 // not modelled in this visual-only pass.
                 let blade = SCNCylinder(radius: CGFloat(outletRadius * 0.88),
                                         height: CGFloat(max(outletRadius * 0.035, 0.0015)))
                 let bladeMaterial = SCNMaterial()
                 bladeMaterial.diffuse.contents = UIColor(red: 0.46, green: 0.51, blue: 0.55, alpha: 1)
                 bladeMaterial.metalness.contents = 0.75
                 bladeMaterial.roughness.contents = 0.4
                 bladeMaterial.isDoubleSided = true
                 blade.materials = [bladeMaterial]
                 let bladeNode = SCNNode(geometry: blade)
                 bladeNode.position = SCNVector3(exitX - sin(turn)*outletRadius*0.18,
                                                 exitY - cos(turn)*outletRadius*0.18, 0)
                 bladeNode.eulerAngles.z = -turn
                 body.addChildNode(bladeNode)
             }
             addLabel("A  " + dimension(fitting.inletWidth),
                      at: SCNVector3(0, 0, b/2 + labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("B  " + dimension(fitting.inletHeight),
                      at: SCNVector3(a/2 + labelOffset/2, 0, 0),
                      to: body, scale: labelSize)
             addLabel("C  Ø " + dimension(fitting.outletWidth),
                      at: SCNVector3(exitX + outletRadius*cos(turn) + labelOffset/2,
                                     exitY + outletRadius*sin(turn), 0),
                      to: body, scale: labelSize)
             let lengthLabel = fitting.hetoMode == .custom
                 ? dimension(fitting.length) : "STANDARD"
             addLabel("D  " + lengthLabel,
                      at: SCNVector3(exitX/2 + labelOffset,
                                     exitY/2 + labelOffset/2, -b/2),
                      to: body, scale: labelSize)
         case .roundReducer, .roundEccentric:
             let inletCollar = max(Float(m(fitting.reducerInletCollarLength)), 0.001)
             let bodyLength = max(Float(m(fitting.effectiveReducerBodyLength)), 0.001)
             let outletCollar = max(Float(m(fitting.reducerOutletCollarLength)), 0.001)
             let length = inletCollar + bodyLength + outletCollar
             let outRadius = max(Float(m(fitting.outletWidth))/2, 0.0005)
             // On flat-top reducers, align the uppermost Z edges at each end.
             let shiftZ = (fitting.reducerMode == .flatTop || fitting.shape == .roundEccentric)
                 ? radius-outRadius : 0
             let start = -length/2
             let bodyStart = start + inletCollar
             let bodyEnd = bodyStart + bodyLength
             let finish = bodyEnd + outletCollar
             body.addChildNode(SCNNode(geometry: mesh(rings: [
                 circularRing(radius: radius, y: start),
                 circularRing(radius: radius, y: bodyStart),
                 circularRing(radius: outRadius, y: bodyEnd, shiftZ: shiftZ),
                 circularRing(radius: outRadius, y: finish, shiftZ: shiftZ)
             ])))
             addLabel("A  " + dimension(fitting.inletWidth),
                      at: SCNVector3(0, start, radius+labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("B  " + dimension(fitting.outletWidth),
                      at: SCNVector3(0, finish, outRadius+shiftZ+labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("C  " + dimension(fitting.reducerOverallLength),
                      at: SCNVector3(radius+labelOffset, 0, 0),
                      to: body, scale: labelSize)
         case .rectEndCap:
             // Closed front face, single open rectangular connection at the rear.
             // The shallow illustrative rim is not a user-entered dimension.
             let a = max(Float(m(fitting.inletWidth)), 0.001)
             let b = max(Float(m(fitting.inletHeight)), 0.001)
             let rim = max(Float(m(0.5)), min(a, b) * 0.05)
             body.addChildNode(SCNNode(geometry: mesh(rings: [
                 rectangularEnd(width: a, depth: b, y: -rim/2),
                 rectangularEnd(width: a, depth: b, y: rim/2)
             ], closeEnd: true)))
             addLabel("A  " + dimension(fitting.inletWidth),
                      at: SCNVector3(0, 0, b/2 + labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("B  " + dimension(fitting.inletHeight),
                      at: SCNVector3(a/2 + labelOffset/2, 0, 0),
                      to: body, scale: labelSize)
         case .rectElbow45, .rectElbow90, .rectRadiusElbow:
             // A swept rectangular wall. Square-throat and radius-elbow types
             // use different inside bend radii, without decorative break lines.
             let a = max(Float(m(fitting.inletWidth)), 0.001)
             let b = max(Float(m(fitting.inletHeight)), 0.001)
             let c = max(Float(m(fitting.outletWidth)), 0.001)
             let d = max(Float(m(fitting.outletHeight)), 0.001)
             let isRadius = fitting.shape == .rectRadiusElbow
             let sweep = fitting.shape == .rectElbow45 ? Float.pi / 4 : Float.pi / 2
             let inside = isRadius ? max(Float(m(fitting.radius)), 0.001) : Float(0.001)
             let centerlineRadius = inside + a/2
             let straightIn = isRadius ? Float(0) : max(Float(m(fitting.straightIn)), 0)
             let straightOut = isRadius ? Float(0) : max(Float(m(fitting.straightOut)), 0)
             let topShift = isRadius ? Float(m(fitting.verticalValue)) : Float(0)
             var rings: [[SCNVector3]] = []
             if straightIn > 0.001 {
                 rings.append(bentRectangle(x: 0, y: -straightIn, angle: 0,
                                            width: a, depth: b))
             }
             rings.append(bentRectangle(x: 0, y: 0, angle: 0, width: a, depth: b))
             let sections = fitting.shape == .rectElbow45 ? 14 : 24
             for section in 1...sections {
                 let t = Float(section) / Float(sections)
                 let theta = sweep * t
                 let cx = centerlineRadius * (1 - cos(theta))
                 let cy = centerlineRadius * sin(theta)
                 let width = a + (c - a) * t
                 let depth = b + (d - b) * t
                 rings.append(bentRectangle(x: cx, y: cy, angle: theta,
                                            width: width, depth: depth,
                                            zShift: topShift * t))
             }
             let exitX = centerlineRadius * (1 - cos(sweep))
             let exitY = centerlineRadius * sin(sweep)
             if straightOut > 0.001 {
                 rings.append(bentRectangle(x: exitX + sin(sweep)*straightOut,
                                            y: exitY + cos(sweep)*straightOut,
                                            angle: sweep, width: c, depth: d,
                                            zShift: topShift))
             }
             body.addChildNode(SCNNode(geometry: mesh(rings: rings)))
             addLabel("A  " + dimension(fitting.inletWidth),
                      at: SCNVector3(0, -straightIn, b/2 + labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("B  " + dimension(fitting.inletHeight),
                      at: SCNVector3(a/2 + labelOffset/2, -straightIn, 0),
                      to: body, scale: labelSize)
             addLabel("C  " + dimension(fitting.outletWidth),
                      at: SCNVector3(exitX + sin(sweep)*straightOut,
                                     exitY + cos(sweep)*straightOut,
                                     topShift + d/2 + labelOffset/2),
                      to: body, scale: labelSize)
             addLabel("D  " + dimension(fitting.outletHeight),
                      at: SCNVector3(exitX + c/2 + labelOffset/2, exitY,
                                     topShift),
                      to: body, scale: labelSize)
             if isRadius {
                 addLabel("E  Radius " + dimension(fitting.radius),
                          at: SCNVector3(centerlineRadius * 0.65, centerlineRadius * 0.45,
                                         -b/2 - labelOffset/2),
                          to: body, scale: labelSize * 0.85)
                 addLabel("F  Shift " + dimension(fitting.verticalValue),
                          at: SCNVector3(exitX + labelOffset, exitY,
                                         topShift - d/2 - labelOffset/2),
                          to: body, scale: labelSize * 0.85)
             } else {
                 addLabel("E  " + dimension(fitting.straightIn),
                          at: SCNVector3(-a/2 - labelOffset/2, -straightIn/2, 0),
                          to: body, scale: labelSize * 0.85)
                 addLabel("F  " + dimension(fitting.straightOut),
                          at: SCNVector3(exitX + sin(sweep)*straightOut/2 + labelOffset/2,
                                         exitY + cos(sweep)*straightOut/2,
                                         -d/2 - labelOffset/2),
                          to: body, scale: labelSize * 0.85)
             }
         case .rectTee:
             addTee(to: body, labelOffset: labelOffset, labelSize: labelSize)
         case .roundEndCap:
             // A closed disk, one open end. Display a shallow rim for clarity.
             let depth = max(diameter*0.05, 0.006)
             body.addChildNode(SCNNode(geometry: mesh(rings: [
                 circularRing(radius: radius, y: -depth/2),
                 circularRing(radius: radius, y: depth/2)
             ], closeEnd: true)))
             addLabel("A  " + dimension(fitting.inletWidth), at: SCNVector3(0, 0, radius+labelOffset/2), to: body, scale: labelSize)
         case .roundElbow45, .roundElbow90:
             let angle = Float(fitting.angle * .pi / 180)
             let bendRadius = radius * Float(fitting.radiusFactor == .one ? 2.0 : 3.0)
             let sections = max(16, Int(ceil(fitting.angle/4)))
             let rings = (0...sections).map { step -> [SCNVector3] in
                 let theta = angle * Float(step)/Float(sections)
                 let cx = bendRadius*(1-cos(theta))
                 let cy = bendRadius*sin(theta)
                 return (0..<64).map { index in
                     let phi = Float(index)*2*Float.pi/64
                     let radial = radius*cos(phi)
                     return SCNVector3(cx + radial*cos(theta),
                                       cy - radial*sin(theta),
                                       radius*sin(phi))
                 }
             }
             body.addChildNode(SCNNode(geometry: mesh(rings: rings)))
             addLabel("A  " + dimension(fitting.inletWidth), at: SCNVector3(0, 0, radius+labelOffset/2), to: body, scale: labelSize)
             addLabel("B  " + String(format: "%g", fitting.angle) + "°", at: SCNVector3(bendRadius*0.65, bendRadius*0.5, radius+labelOffset), to: body, scale: labelSize)
         default: break
         }
         return scene
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
