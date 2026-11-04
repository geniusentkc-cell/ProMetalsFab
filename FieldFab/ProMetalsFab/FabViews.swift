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
                Section {
                    Label("V1 stores jobs on this iPhone. Export PDFs to share with the shop.", systemImage: "iphone")
                        .font(.footnote).foregroundColor(.secondary)
                    NavigationLink("Legacy transition tool") {
                        DuctTransition.ModuleView()
                    }
                } header: { Text("Tools") }
            }
            .navigationTitle("ProMetalsFab")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button { jobName = ""; addingJob = true } label: { Image(systemName: "plus") }
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
    @State private var addingArea = false
    @State private var newAreaName = ""
    @State private var editingArea: FabArea?
    @State private var shareFile: FabExportFile?
    @State private var exportError: String?
    private var job: FabJob? { store.job(jobID) }
    var body: some View {
        List {
            if let job = job {
                Section("Fabrication Requests") {
                    NavigationLink {
                        FabAreaFittingsView(jobID: jobID, areaID: nil)
                    } label: {
                        Label("Unassigned / Job Root (\(job.fittings(in: nil).count))", systemImage: "tray")
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
            Button { newAreaName = ""; addingArea = true } label: { Label("Add Area", systemImage: "folder.badge.plus") }
        }}
        .alert("New Area", isPresented: $addingArea) {
            TextField("Floor or area name", text: $newAreaName)
            Button("Create") {
                let name = newAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, var changed = job {
                    changed.areas.append(FabArea(name: name))
                    store.replace(changed)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Example: Second Floor") }
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
    let onSave: (FabArea) -> Void
    init(area: FabArea, onSave: @escaping (FabArea) -> Void) {
        _area = State(initialValue: area); self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Area") { TextField("Area name", text: $area.name) }
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
            .navigationTitle("Area Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if !area.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onSave(area); dismiss() }
                }}
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
                    Text("No fittings yet. Tap + to create your first fitting.")
                        .foregroundColor(.secondary)
                }
                ForEach(list) { fitting in
                    Button { editing = fitting } label: {
                        HStack(spacing: 12) {
                            Image(systemName: fitting.isRound ? "circle.dotted.circle" : "square.on.square")
                                .font(.title3).foregroundColor(.blue).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fitting.name.isEmpty ? fitting.shape.rawValue : fitting.name)
                                    .font(.headline).foregroundColor(.primary)
                                Text(fitting.shape.rawValue + " · Qty \(fitting.quantity)")
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
                        Label("Export \(area?.name ?? "Job Root") PDF", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(area?.name ?? "Job Root")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
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
    var body: some View {
        NavigationStack {
            List {
                Section("Rectangular") {
                    ForEach(FabShape.allCases.filter { !$0.isRound }) { shape in
                        NavigationLink {
                            newFittingEditor(for: shape)
                        } label: {
                            Label(shape.rawValue, systemImage: "square")
                        }
                    }
                }
                Section("Round") {
                    ForEach(FabShape.allCases.filter(\.isRound)) { shape in
                        NavigationLink {
                            newFittingEditor(for: shape)
                        } label: {
                            Label(shape.rawValue, systemImage: "circle")
                        }
                    }
                }
            }
            .navigationTitle("Select Fitting").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    // The editor is a destination in this NavigationStack, not another stack or sheet.
    // Only the containing selection sheet is dismissed after a successful save.
    private func newFittingEditor(for shape: FabShape) -> some View {
        FabFittingEditor(fitting: .new(shape: shape, areaID: areaID), area: area,
                         dismissAfterSave: false) { new in
            onSave(new)
            dismiss()
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
    init(fitting: FabFitting, area: FabArea?, dismissAfterSave: Bool = true,
         onSave: @escaping (FabFitting) -> Void) {
        _fitting = State(initialValue: fitting)
        self.area = area
        self.dismissAfterSave = dismissAfterSave
        self.onSave = onSave
    }
    private var isRound: Bool { fitting.isRound }
    private var connections: [FabConnection] { isRound ? FabConnection.round : FabConnection.rectangular }
    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField("Inches", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text("in").foregroundColor(.secondary)
        }
    }
    var body: some View {
        Form {
                Section("Fitting") {
                    Text(fitting.shape.rawValue).font(.headline)
                    TextField("Fitting label (optional)", text: $fitting.name)
                    Stepper("Quantity: \(fitting.quantity)", value: $fitting.quantity, in: 1...9999)
                }
                Section("Dimensions — Finished Inches") {
                    number(isRound ? "Inlet diameter" : "Inlet width", $fitting.inletWidth)
                    if !isRound { number("Inlet height", $fitting.inletHeight) }
                    if fitting.shape.needsOutlet {
                        number(isRound || fitting.shape == .squareRound ? "Outlet diameter" : "Outlet width", $fitting.outletWidth)
                        if !isRound && fitting.shape != .squareRound { number("Outlet height", $fitting.outletHeight) }
                    }
                    number(fitting.shape.isElbow ? "Reference length" : "Overall length", $fitting.length)
                    if fitting.shape.isElbow {
                        number("Centerline radius", $fitting.radius)
                        Picker("Bend plane", selection: $fitting.elbowPlane) {
                            ForEach(FabElbowPlane.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    if fitting.shape == .roundTee {
                        number("Branch diameter", $fitting.branchDiameter)
                        number("Lateral angle", $fitting.angle)
                    }
                    if !fitting.shape.isElbow {
                        number("Straight in", $fitting.straightIn)
                        number("Straight out", $fitting.straightOut)
                    }
                }
                if fitting.shape.isTransition {
                    Section("Alignment and Offsets") {
                        Picker("Vertical", selection: $fitting.verticalAlignment) {
                            ForEach(FabVerticalAlignment.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if fitting.verticalAlignment != .centered { number("Vertical value", $fitting.verticalValue) }
                        Picker("Horizontal", selection: $fitting.horizontalAlignment) {
                            ForEach(FabHorizontalAlignment.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if fitting.horizontalAlignment == .centerShift { number("Horizontal center shift", $fitting.horizontalValue) }
                        Text("Outlet center displacement: X \(fabInches(fitting.offsetX)), Y \(fabInches(fitting.offsetY))")
                            .font(.caption).foregroundColor(.secondary)
                        if !isRound {
                            Text("Top drop \(fabInches(fitting.topChange)) · Bottom rise \(fabInches(fitting.bottomChange))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("Connections") {
                    Picker("Inlet", selection: $fitting.inletConnection) {
                        ForEach(connections) { Text($0.rawValue).tag($0) }
                    }
                    if fitting.inletConnection == .special { TextField("Inlet connection details", text: $fitting.inletSpecial) }
                    Picker("Outlet", selection: $fitting.outletConnection) {
                        ForEach(connections) { Text($0.rawValue).tag($0) }
                    }
                    if fitting.outletConnection == .special { TextField("Outlet connection details", text: $fitting.outletSpecial) }
                }
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
                        Text("Area defaults can be overridden independently for type and thickness.")
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
                        }
                        .disabled(fitting.linerOverride == nil && area != nil)
                    }
                }
                Section("Shop Notes") {
                    TextEditor(text: $fitting.notes).frame(minHeight: 78)
                }
                Section {
                    Text("Dimensions are entered exactly as specified. No automatic liner or insulation allowance is applied. PDF drawings are assembly schematics, not developed patterns.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Fitting Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
