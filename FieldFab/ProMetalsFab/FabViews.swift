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
                    Text("Select a fitting to enter its dimensions. Letter keys are consistent across the fitting library.")
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

    init(fitting: FabFitting, area: FabArea?, dismissAfterSave: Bool = true,
         onSave: @escaping (FabFitting) -> Void) {
        var editable = fitting
        if editable.isRound {
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
        _fitting = State(initialValue: editable)
        self.area = area
        self.dismissAfterSave = dismissAfterSave
        self.onSave = onSave
    }
    private var isRound: Bool { fitting.isRound }
    private var isRoundElbow: Bool { fitting.shape.isRoundElbow }
    private var isRectElbow: Bool { fitting.shape.isRectElbow }
    private var connections: [FabConnection] { isRound ? FabConnection.round : FabConnection.rectangular }
    private var diameterInput: Binding<Double> {
        Binding(get: { fitting.inletWidth }, set: { newValue in
            fitting.inletWidth = newValue
            fitting.inletHeight = newValue
            if fitting.shape.isRoundElbow || fitting.shape == .roundStraight {
                fitting.outletWidth = newValue
                fitting.outletHeight = newValue
            }
        })
    }
    private var rectangularWidth: Binding<Double> {
        Binding(get: { fitting.inletWidth }, set: { newValue in
            fitting.inletWidth = newValue
            if fitting.shape.isRectElbow || fitting.shape == .rectStraight { fitting.outletWidth = newValue }
        })
    }
    private var rectangularDepth: Binding<Double> {
        Binding(get: { fitting.inletHeight }, set: { newValue in
            fitting.inletHeight = newValue
            if fitting.shape.isRectElbow || fitting.shape == .rectStraight { fitting.outletHeight = newValue }
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
        Binding(get: { isRound ? fitting.inletConnection.normalizedRound : fitting.inletConnection },
                set: { fitting.inletConnection = $0 })
    }
    private var outputConnection: Binding<FabConnection> {
        Binding(get: { isRound ? fitting.outletConnection.normalizedRound : fitting.outletConnection },
                set: { fitting.outletConnection = $0 })
    }
    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField("Inches", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 88)
            Text("in").foregroundColor(.secondary)
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
    var body: some View {
        Form {
            Section("Fitting") {
                Text(fitting.shape.displayName).font(.headline)
                TextField("Fitting label (optional)", text: $fitting.name)
                Stepper("Quantity: \(fitting.quantity)", value: $fitting.quantity, in: 1...9999)
            }
            if !fitting.shape.isCustom {
                Section("Fitting Diagram · Dimension Letters") {
                    FabFittingGlyph(shape: fitting.shape)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                    Text(fitting.dimensionLegend)
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Section("Dimensions — Finished Inches") {
                    if isRound {
                        number("A — Diameter In", diameterInput)
                        if isRoundElbow || fitting.shape == .roundStraight {
                            matched("C — Diameter Out", value: fitting.inletWidth)
                        } else {
                            number("C — Diameter Out", $fitting.outletWidth)
                        }
                    } else {
                        number("A — Width In", rectangularWidth)
                        number("B — Depth In", rectangularDepth)
                        if isRectElbow || fitting.shape == .rectStraight {
                            matched("C — Width Out", value: fitting.inletWidth)
                            matched("D — Depth Out", value: fitting.inletHeight)
                        } else if fitting.shape == .squareRound {
                            number("C — Diameter Out", $fitting.outletWidth)
                        } else if fitting.shape.needsOutlet {
                            number("C — Width Out", $fitting.outletWidth)
                            number("D — Depth Out", $fitting.outletHeight)
                        }
                    }
                    if isRoundElbow {
                        Picker("J — Elbow Angle", selection: elbowAngle) {
                            Text("90°").tag(90)
                            Text("45°").tag(45)
                        }.pickerStyle(.segmented)
                    } else if isRectElbow {
                        HStack {
                            Text("J — Elbow Angle")
                            Spacer()
                            Text(fitting.shape == .rectElbow45 ? "45°" : "90°")
                        }
                        number("K — Throat Straight In", $fitting.straightIn)
                        number("L — Throat Straight Out", $fitting.straightOut)
                    } else {
                        number("E — Overall Length", $fitting.length)
                        if !fitting.shape.isStraight {
                            number("K — Straight In", $fitting.straightIn)
                            number("L — Straight Out", $fitting.straightOut)
                        }
                    }
                    if fitting.shape == .roundTee {
                        number("M — Branch Diameter", $fitting.branchDiameter)
                        number("J — Lateral Angle", $fitting.angle)
                    }
                }
                if fitting.shape.isTransition {
                    Section("Alignment and Offsets") {
                        Picker("Vertical", selection: $fitting.verticalAlignment) {
                            ForEach(FabVerticalAlignment.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if fitting.verticalAlignment != .centered {
                            number("G — Vertical Alignment Value", $fitting.verticalValue)
                        }
                        Picker("Horizontal", selection: $fitting.horizontalAlignment) {
                            ForEach(FabHorizontalAlignment.allCases) { Text($0.rawValue).tag($0) }
                        }
                        if fitting.horizontalAlignment == .centerShift {
                            number("F — Horizontal Center Shift", $fitting.horizontalValue)
                        }
                        Text("F — Outlet X shift \(fabInches(fitting.offsetX)) · G — Outlet Y shift \(fabInches(fitting.offsetY))")
                            .font(.caption).foregroundColor(.secondary)
                        if !isRound {
                            Text("Top change \(fabInches(fitting.topChange)) · Bottom change \(fabInches(fitting.bottomChange))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("Connections") {
                    Picker("Connection In", selection: inputConnection) {
                        ForEach(connections) { Text($0.rawValue).tag($0) }
                    }
                    if inputConnection.wrappedValue == .custom || inputConnection.wrappedValue == .special {
                        TextField("Custom connection In", text: $fitting.inletSpecial)
                    }
                    Picker("Connection Out", selection: outputConnection) {
                        ForEach(connections) { Text($0.rawValue).tag($0) }
                    }
                    if outputConnection.wrappedValue == .custom || outputConnection.wrappedValue == .special {
                        TextField("Custom connection Out", text: $fitting.outletSpecial)
                    }
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
            Section(fitting.shape.isCustom ? "Describe Custom Fitting (Required)" : "Shop Notes") {
                TextEditor(text: $fitting.notes).frame(minHeight: 78)
            }
            Section {
                Text("Dimensions are finished inches; liner and insulation never automatically change the entered measurements. Drawings are labeled schematics, not flat patterns.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
        .navigationTitle("Fitting Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    }
}

// Original monochrome schematic icon artwork, not derived from third-party images.
// A/B and C/D stay consistent from the icon through the PDF and input form.
struct FabFittingGlyph: View {
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
            case .rectStraight, .roundStraight:
                outline.addRect(CGRect(x: w*0.20, y: h*0.32, width: w*0.60, height: h*0.36))
                if shape.isRound {
                    outline.addEllipse(in: CGRect(x: w*0.18, y: h*0.32, width: w*0.10, height: h*0.36))
                    outline.addEllipse(in: CGRect(x: w*0.74, y: h*0.32, width: w*0.10, height: h*0.36))
                }
            case .rectTransition, .squareRound, .roundReducer, .roundEccentric:
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
