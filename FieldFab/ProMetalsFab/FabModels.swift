import Foundation

import Combine
// ProMetalsFab V1 uses inches throughout. Entered finished dimensions are NEVER
// changed to compensate for liner or insulation. PractiCAM handles allowances.
enum FabShape: String, Codable, CaseIterable, Identifiable {
    case rectStraight = "Rectangular Straight"
    case rectTransition = "Rectangular Transition"
    case rectElbow45 = "Rectangular 45° Elbow"
    case rectElbow90 = "Rectangular 90° Elbow"
    case rectOffset = "Rectangular Offset" // legacy V2 jobs
    case rectRadiusElbow = "Rectangular Radius Elbow"
    case rectTee = "Rectangular Square Tee"
    case rectEndCap = "Rectangular End Cap"
    case squareRound = "Square to Round"
    // Legacy round shapes remain decodable for previous saved jobs.
    case roundStraight = "Round Straight"
    case roundSpiral = "Round Spiral Pipe"
    case roundHeto90 = "90° HETO"
    case roundHeto45 = "45° HETO"
    case roundEndCap = "Round End Cap"
    case roundReducer = "Round Concentric Reducer"
    case roundEccentric = "Round Eccentric Reducer"
    case roundElbow45 = "Round 45° Elbow"
    case roundElbow90 = "Round 90° Elbow"
    case roundOffset = "Round Offset"
    case roundTee = "Round Tee / Lateral"
    case custom = "Custom Fitting"
    var id: String { rawValue }
    // Keep both underlying elbow cases for previously saved jobs, but display one
    // selectable round elbow with an angle picker.
    static var libraryChoices: [FabShape] {
        // The old rectangular offset remains decodable, but is not in the approved V3 catalog.
        // V4 approved round catalog: six entries only. Older fitting types stay
        // decodable and can still be edited in preexisting jobs.
        let approvedRound: [FabShape] = [.roundElbow90, .roundReducer, .roundHeto90,
                                        .roundHeto45, .roundSpiral, .roundEndCap]
        return allCases.filter { $0.isCatalogRect } + approvedRound + [.custom]
    }
    var isCatalogRect: Bool {
        switch self {
        case .rectStraight, .rectTransition, .rectElbow45, .rectElbow90,
             .rectRadiusElbow, .rectTee, .squareRound, .rectEndCap: return true
        default: return false
        }
    }
    var isCatalogRound: Bool {
        switch self {
        case .roundElbow45, .roundElbow90, .roundReducer, .roundHeto90,
             .roundHeto45, .roundSpiral, .roundEndCap: return true
        default: return false
        }
    }
    var isHeto: Bool { self == .roundHeto90 || self == .roundHeto45 }
    var isRoundReducer: Bool { self == .roundReducer || self == .roundEccentric }
    var isRoundEndCap: Bool { self == .roundEndCap }
    var isRoundSpiral: Bool { self == .roundSpiral }
    var displayName: String {
        switch self {
        case .roundElbow45, .roundElbow90: return "Round Elbow"
        case .roundReducer: return "Round Reducer"
        case .rectElbow45: return "45° Square Elbow"
        case .rectElbow90: return "90° Square Elbow with Vanes"
        case .rectRadiusElbow: return "Rectangular Radius Elbow"
        case .rectTee: return "Square Tee"
        case .rectEndCap: return "Rectangular End Cap"
        default: return rawValue
        }
    }
    var isRectElbow: Bool { self == .rectElbow45 || self == .rectElbow90 || self == .rectRadiusElbow }
    var isSquareElbow: Bool { self == .rectElbow45 || self == .rectElbow90 }
    var isRoundElbow: Bool { self == .roundElbow45 || self == .roundElbow90 }
    var isStraight: Bool { self == .rectStraight || self == .roundStraight }
    var isCustom: Bool { self == .custom }
    var isRound: Bool {
        switch self {
        case .roundStraight, .roundSpiral, .roundReducer, .roundEccentric, .roundElbow45,
             .roundElbow90, .roundHeto90, .roundHeto45, .roundEndCap,
             .roundOffset, .roundTee: return true
        default: return false
        }
    }
    var isTransition: Bool { self == .rectTransition || self == .rectOffset || self == .squareRound || self == .roundReducer || self == .roundEccentric || self == .roundOffset }
    var isElbow: Bool { isRectElbow || isRoundElbow }
    var needsOutlet: Bool { isTransition || isRectElbow || isHeto || self == .roundTee || self == .rectTee }
    var singleOpening: Bool { self == .rectEndCap || self == .roundEndCap }
}

enum FabConnection: String, Codable, CaseIterable, Identifiable {
    case slipDrive = "S&D", driveSlip = "D&S", tdf = "TDF", special = "Special"
    // Older names are retained so V1 saved jobs remain decodable.
    case plain = "Plain", beaded = "Beaded", flanged = "Flanged"
    case raw = "Raw", bead = "Bead", custom = "Custom", flangeOut = "1\" Flange Out"
    case roundTDC = "TDC Flange"
    var id: String { rawValue }
    static var rectangular: [FabConnection] { [.slipDrive, .driveSlip, .tdf, .raw, .flangeOut, .custom] }
    static var round: [FabConnection] { [.raw, .bead, .roundTDC, .custom] }
    static var spiral: [FabConnection] { [.raw, .custom] }
    var normalizedRound: FabConnection {
        switch self {
        case .plain: return .raw
        case .beaded: return .bead
        case .special, .flanged: return .custom
        default: return self
        }
    }
}

enum FabRoundInsulation: String, Codable, CaseIterable, Identifiable {
    case none = "None", doubleWall = "Double Wall", spiracoustic = "Spiracoustic"
    var id: String { rawValue }
}

enum FabLiner: String, Codable, CaseIterable, Identifiable {
    case none = "None", half = "1/2\"", one = "1\"", oneHalf = "1 1/2\"", two = "2\""
    var id: String { rawValue }
}

enum FabThickness: String, Codable, CaseIterable, Identifiable {
    case half = "1/2\"", one = "1\"", oneHalf = "1 1/2\"", two = "2\""
    var id: String { rawValue }
}

enum FabElbowPlane: String, Codable, CaseIterable, Identifiable {
    case horizontal = "Horizontal (plan bend)", vertical = "Vertical (elevation bend)"
    var id: String { rawValue }
}

enum FabVerticalAlignment: String, Codable, CaseIterable, Identifiable {
    case centered = "Centered", topDown = "Top Down", bottomUp = "Bottom Up", centerShift = "Center Shift"
    var id: String { rawValue }
}

enum FabHorizontalAlignment: String, Codable, CaseIterable, Identifiable {
    case centered = "Centered", left = "Left Flush", right = "Right Flush", centerShift = "Center Shift"
    var id: String { rawValue }
}

enum FabMaterial: String, Codable, CaseIterable, Identifiable {
    case galvanized = "Galvanized"
    case stainless = "Stainless Steel"
    case paintGrip = "Paint Grip"
    case aluminum = "Aluminum"
    var id: String { rawValue }
}

enum FabGauge: String, Codable, CaseIterable, Identifiable {
    case ga10 = "10", ga12 = "12", ga14 = "14", ga16 = "16", ga18 = "18"
    case ga20 = "20", ga22 = "22", ga24 = "24", ga26 = "26", custom = "Custom"
    var id: String { rawValue }
}

enum FabElbowFabrication: String, Codable, CaseIterable, Identifiable {
    case fabricated = "Fabricated", purchased = "Purchased"
    var id: String { rawValue }
}

enum FabRadiusFactor: String, Codable, CaseIterable, Identifiable {
    case onePointFive = "1.5", one = "1.0"
    var id: String { rawValue }
    var displayName: String { self == .onePointFive ? "1.5 (standard)" : "1" }
}

enum FabReducerAlignment: String, Codable, CaseIterable, Identifiable {
    case centerline = "Centerline", flatTop = "Flat Top"
    var id: String { rawValue }
}

enum FabHetoLengthMode: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard", custom = "Custom"
    var id: String { rawValue }
}

struct FabArea: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rectangularLiner: FabLiner = .none
    var roundInsulation: FabRoundInsulation = .none
    var roundThickness: FabThickness = .one
    // Optional for backwards-compatible decoding of pre-V4 persisted areas.
    var material: FabMaterial? = nil
    var gauge: FabGauge? = nil
    var customGauge: String? = nil
    var defaultMaterial: FabMaterial { material ?? .galvanized }
    var defaultGauge: FabGauge { gauge ?? .ga24 }
    var defaultGaugeLabel: String {
        defaultGauge == .custom ? (customGauge ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : defaultGauge.rawValue + " GA"
    }
}

struct FabFitting: Codable, Identifiable, Equatable {
    var id = UUID()
    var areaID: UUID? = nil // nil means the root of the job
    var name: String = ""
    var shape: FabShape = .rectTransition
    var quantity: Int = 1
    var inletWidth: Double = 24
    var inletHeight: Double = 18
    var outletWidth: Double = 18
    var outletHeight: Double = 12
    var length: Double = 24
    var straightIn: Double = 2
    var straightOut: Double = 2
    var angle: Double = 90
    var radius: Double = 12
    var elbowPlane: FabElbowPlane = .horizontal
    var branchDiameter: Double = 8
    var verticalAlignment: FabVerticalAlignment = .centered
    var verticalValue: Double = 0
    var horizontalAlignment: FabHorizontalAlignment = .centered
    var horizontalValue: Double = 0
    var inletConnection: FabConnection = .slipDrive
    var outletConnection: FabConnection = .slipDrive
    var inletSpecial: String = ""
    var outletSpecial: String = ""
    var linerOverride: FabLiner? = nil
    var roundInsulationOverride: FabRoundInsulation? = nil
    var roundThicknessOverride: FabThickness? = nil
    // V3 optional fields: synthesized Codable decoding retains all V1/V2 saved job files.
    // Square Tee: A/B = main, C/D = left, E/F = right; G,H,I,J = independent throats.
    var teeRightWidth: Double? = nil
    var teeRightDepth: Double? = nil
    var teeThroatG: Double? = nil
    var teeThroatH: Double? = nil
    var teeThroatI: Double? = nil
    var teeThroatJ: Double? = nil
    var teeRightConnection: FabConnection? = nil
    var teeRightSpecial: String? = nil
    var hasDamper: Bool? = nil
    // All newly added values stay Optional to decode V1/V2/V3 JSON unmodified.
    var materialOverride: FabMaterial? = nil
    var gaugeOverride: FabGauge? = nil
    var customGaugeOverride: String? = nil
    var elbowFabrication: FabElbowFabrication? = nil
    var elbowRadiusFactor: FabRadiusFactor? = nil
    var elbowAngleCustom: Bool? = nil
    var reducerAlignment: FabReducerAlignment? = nil
    var hetoLengthMode: FabHetoLengthMode? = nil
    var notes: String = ""

    var isRound: Bool { shape.isRound }
    func effectiveMaterial(in area: FabArea?) -> FabMaterial { materialOverride ?? area?.defaultMaterial ?? .galvanized }
    func effectiveGauge(in area: FabArea?) -> FabGauge { gaugeOverride ?? area?.defaultGauge ?? .ga24 }
    func effectiveGaugeLabel(in area: FabArea?) -> String {
        let selection = effectiveGauge(in: area)
        if selection == .custom {
            return gaugeOverride == nil ? (area?.customGauge ?? "") : (customGaugeOverride ?? "")
        }
        return selection.rawValue + " GA"
    }
    var fabricationType: FabElbowFabrication { elbowFabrication ?? .fabricated }
    var radiusFactor: FabRadiusFactor { elbowRadiusFactor ?? .onePointFive }
    var angleIsCustom: Bool { elbowAngleCustom ?? false }
    var reducerMode: FabReducerAlignment { reducerAlignment ?? .centerline }
    var hetoMode: FabHetoLengthMode { hetoLengthMode ?? .standard }
    var needsCustomLength: Bool { shape.isHeto && hetoMode == .custom }
    var effectiveOutletHeight: Double {
        (shape.isRound && !shape.isHeto || shape == .squareRound || shape.isHeto) ? outletWidth : outletHeight
    }
    func effectiveLiner(in area: FabArea?) -> FabLiner { linerOverride ?? area?.rectangularLiner ?? .none }
    func effectiveRoundInsulation(in area: FabArea?) -> FabRoundInsulation { roundInsulationOverride ?? area?.roundInsulation ?? .none }
    func effectiveRoundThickness(in area: FabArea?) -> FabThickness { roundThicknessOverride ?? area?.roundThickness ?? .one }
    var effectiveOutletWidth: Double { shape.isRoundElbow || shape.isStraight ? inletWidth : outletWidth }
    var effectiveOutletDepth: Double { shape.isRoundElbow || shape.isStraight ? inletHeight : outletHeight }
    private func connectionLabel(_ connection: FabConnection, description: String) -> String {
        let selected = (isRound && !shape.isHeto) ? connection.normalizedRound : connection
        if selected == .special || selected == .custom {
            return "Custom: " + (description.isEmpty ? "Unspecified" : description)
        }
        return selected.rawValue
    }
    func inletLabel() -> String { connectionLabel(inletConnection, description: inletSpecial) }
    func outletLabel() -> String {
        let chosen = (isRound || shape == .squareRound) ? outletConnection.normalizedRound : outletConnection
        if shape.isHeto {
            return chosen == .custom ? "Custom: " + (outletSpecial.isEmpty ? "Unspecified" : outletSpecial) : chosen.rawValue
        }
        return connectionLabel(chosen, description: outletSpecial)
    }
    func teeRightLabel() -> String { connectionLabel(teeRightConnection ?? .slipDrive, description: teeRightSpecial ?? "") }
    var isDampered: Bool { hasDamper ?? false }
    var teeE: Double { teeRightWidth ?? inletWidth }
    var teeF: Double { teeRightDepth ?? inletHeight }
    var teeG: Double { teeThroatG ?? 6 }
    var teeH: Double { teeThroatH ?? 6 }
    var teeI: Double { teeThroatI ?? 6 }
    var teeJ: Double { teeThroatJ ?? 6 }
    var transitionLeft: Double { leftChange }
    var transitionRight: Double { rightChange }
    var transitionTop: Double { topChange }
    var transitionBottom: Double { bottomChange }
    mutating func setTransitionLeft(_ left: Double) {
        horizontalAlignment = .centerShift
        horizontalValue = left - (inletWidth - outletWidth)/2
    }
    mutating func setTransitionRight(_ right: Double) {
        setTransitionLeft(inletWidth - outletWidth - right)
    }
    mutating func setTransitionTop(_ top: Double) {
        verticalAlignment = .centerShift
        verticalValue = (inletHeight - outletHeight)/2 - top
    }
    mutating func setTransitionBottom(_ bottom: Double) {
        setTransitionTop(inletHeight - outletHeight - bottom)
    }
    mutating func centerTransition() {
        verticalAlignment = .centered; verticalValue = 0
        horizontalAlignment = .centered; horizontalValue = 0
    }
    var dimensionLegend: String {
        if shape.isCustom { return "Describe custom fitting in Notes" }
        if shape.isRoundElbow { return "A Diameter (both ends) · B Elbow Angle" }
        if shape.isRoundReducer { return "A Diameter In · B Diameter Out · C Length" }
        if shape.isHeto { return "A × B Rectangular Opening · C Round Diameter · D Length" }
        if shape.isRoundSpiral { return "A Pipe Length · B Diameter (both ends)" }
        if shape.isRoundEndCap { return "A Diameter · one open connection" }
        if shape.isRound { return "A Diameter In · C Diameter Out · E Length" }
        if shape.isSquareElbow { return "A/B = In · C/D = Out · E/F = separate throat lengths" }
        if shape == .rectRadiusElbow { return "A/B = In · C/D = Out · E = interior radius · F = top shift" }
        if shape == .rectTee { return "A/B = Bottom · C/D = Left · E/F = Right · G/H/I/J = throats" }
        if shape == .squareRound { return "A Width · B Depth · C Diameter · D Length" }
        if shape == .rectEndCap { return "A Width · B Depth" }
        if shape == .rectTransition { return "A/B = In · C/D = Out · center by default; sides editable" }
        return "A Width In · B Depth In · C Width Out · D Depth Out · E Length"
    }

    // Center displacement of the outlet, relative to inlet, in finished inches.
    // Positive Y is up; a Top Down value of 2 lowers the outlet's top by 2.
    var offsetY: Double {
        if shape.isRoundReducer && reducerMode == .flatTop {
            return (inletWidth - outletWidth) / 2
        }
        let input = shape.isRound ? inletWidth : inletHeight
        let output = shape.needsOutlet ? effectiveOutletHeight : input
        switch verticalAlignment {
        case .centered: return 0
        case .topDown: return (input - output) / 2 - verticalValue
        case .bottomUp: return (output - input) / 2 + verticalValue
        case .centerShift: return verticalValue
        }
    }
    // Positive X is right in plan view.
    var offsetX: Double {
        let input = inletWidth
        let output = shape.needsOutlet ? outletWidth : inletWidth
        switch horizontalAlignment {
        case .centered: return 0
        case .left: return (output - input) / 2
        case .right: return (input - output) / 2
        case .centerShift: return horizontalValue
        }
    }
    var topChange: Double { (inletHeight - (shape.needsOutlet ? effectiveOutletHeight : inletHeight)) / 2 - offsetY }
    var bottomChange: Double { (inletHeight - (shape.needsOutlet ? effectiveOutletHeight : inletHeight)) / 2 + offsetY }
    var leftChange: Double { (inletWidth - (shape.needsOutlet ? outletWidth : inletWidth)) / 2 + offsetX }
    var rightChange: Double { (inletWidth - (shape.needsOutlet ? outletWidth : inletWidth)) / 2 - offsetX }
    var validationMessage: String? {
        guard quantity > 0 else { return "Quantity must be at least 1." }
        if gaugeOverride == .custom &&
           (customGaugeOverride ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the custom gauge or thickness for this fitting."
        }
        if shape.isCustom {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Describe the custom fitting in Shop Notes." : nil
        }
        let values = [inletWidth, inletHeight, outletWidth, outletHeight, length,
                      straightIn, straightOut, angle, radius, branchDiameter,
                      verticalValue, horizontalValue] +
                     [teeRightWidth, teeRightDepth, teeThroatG, teeThroatH, teeThroatI, teeThroatJ].compactMap { $0 }
        guard values.allSatisfy({ $0.isFinite }) else { return "Measurements must be valid finite numbers." }
        guard inletWidth > 0, (!shape.isRound && inletHeight > 0 || shape.isRound) else {
            return "Inlet dimensions must be greater than zero."
        }
        if !shape.singleOpening && !shape.isHeto && shape != .rectTee && !shape.isElbow && length <= 0 {
            return "Length must be greater than zero."
        }
        if shape.isHeto && needsCustomLength && length <= 0 { return "Custom HETO length must be greater than zero." }
        if shape.isHeto && inletHeight <= 0 { return "HETO depth must be greater than zero." }
        if shape.isRoundElbow && (angle <= 0 || angle > 180) { return "Enter an elbow angle greater than 0° and at most 180°." }
        if shape == .rectRadiusElbow && radius <= 0 { return "Inside radius must be greater than zero." }
        if shape == .rectTee {
            guard teeE > 0, teeF > 0 else { return "The right opening must have positive dimensions." }
            guard [teeG, teeH, teeI, teeJ].allSatisfy({ $0 >= 0 }) else {
                return "Tee throat lengths cannot be negative."
            }
        }
        if shape.needsOutlet && (outletWidth <= 0 || (!shape.isRound && shape != .squareRound && outletHeight <= 0)) {
            return "Outlet dimensions must be greater than zero."
        }
        if shape.isSquareElbow && (straightIn < 0 || straightOut < 0) {
            return "Throat straight lengths cannot be negative."
        }
        if !shape.isElbow && !shape.isStraight && !shape.isCatalogRound && shape != .rectTee && shape != .rectEndCap && (straightIn < 0 || straightOut < 0 || straightIn + straightOut > length) {
            return "Straight-in plus straight-out must not exceed overall length."
        }
        if shape == .roundTee && branchDiameter <= 0 { return "Branch diameter must be greater than zero." }
        if shape.isRound && (inletConnection.normalizedRound == .custom && inletSpecial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             (!shape.singleOpening && outletConnection.normalizedRound == .custom && outletSpecial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) {
            return "Enter the description for each Custom round connection."
        }
        func isBlank(_ v: String) -> Bool { v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if inletConnection == .custom || inletConnection == .special {
            if isBlank(inletSpecial) { return "Describe the custom inlet connection." }
        }
        if !shape.singleOpening && (outletConnection == .custom || outletConnection == .special) {
            if isBlank(outletSpecial) { return "Describe the custom outlet connection." }
        }
        if shape == .rectTee && (teeRightConnection ?? .slipDrive) == .custom && isBlank(teeRightSpecial ?? "") {
            return "Describe the custom right-branch connection."
        }
        return nil
    }
    static func new(shape: FabShape, areaID: UUID?) -> FabFitting {
        var fitting = FabFitting()
        fitting.shape = shape
        fitting.areaID = areaID
        if shape.isRound {
            fitting.inletWidth = 12; fitting.inletHeight = 12
            fitting.outletWidth = 8; fitting.outletHeight = 8
            fitting.inletConnection = .raw; fitting.outletConnection = .raw
        }
        if shape == .rectStraight || shape == .roundStraight || shape == .rectOffset || shape == .roundOffset || shape == .roundTee {
            fitting.outletWidth = fitting.inletWidth; fitting.outletHeight = fitting.inletHeight
        }
        if shape.isRectElbow {
            fitting.straightIn = 6; fitting.straightOut = 6
            fitting.outletWidth = fitting.inletWidth; fitting.outletHeight = fitting.inletHeight
        }
        if shape == .rectRadiusElbow { fitting.radius = 12; fitting.verticalAlignment = .centerShift }
        if shape == .rectTee {
            fitting.teeRightWidth = 18; fitting.teeRightDepth = 12
            fitting.teeThroatG = 6; fitting.teeThroatH = 6
            fitting.teeThroatI = 6; fitting.teeThroatJ = 6
            fitting.teeRightConnection = .slipDrive
            fitting.outletWidth = 18; fitting.outletHeight = 12
        }
        if shape == .squareRound { fitting.length = 12; fitting.outletConnection = .raw; fitting.hasDamper = false }
        if shape == .rectEndCap { fitting.outletWidth = fitting.inletWidth; fitting.outletHeight = fitting.inletHeight }
        if shape == .rectTransition { fitting.centerTransition() }
        if shape.isHeto {
            fitting.inletWidth = 12; fitting.inletHeight = 8
            fitting.outletWidth = 8; fitting.outletHeight = 8
            fitting.length = 12; fitting.hetoLengthMode = .standard
            fitting.inletConnection = .flangeOut; fitting.outletConnection = .bead
            fitting.hasDamper = false
        }
        if shape == .roundSpiral {
            fitting.inletWidth = 12; fitting.inletHeight = 12
            fitting.outletWidth = 12; fitting.outletHeight = 12
            fitting.length = 60
        }
        if shape.isRoundEndCap { fitting.inletWidth = 12; fitting.inletConnection = .raw }
        if shape.isRoundReducer { fitting.reducerAlignment = .centerline }
        if shape.isRoundElbow {
            fitting.outletWidth = fitting.inletWidth; fitting.outletHeight = fitting.inletHeight
            fitting.elbowRadiusFactor = .onePointFive
            fitting.elbowFabrication = .fabricated
            fitting.elbowAngleCustom = false
        }
        if shape == .roundEccentric { fitting.verticalAlignment = .topDown }
        if shape == .squareRound { fitting.outletWidth = 12 }
        if shape == .rectElbow45 || shape == .roundElbow45 { fitting.angle = 45 }
        if shape.isElbow { fitting.length = 24 }
        return fitting
    }
}

struct FabJob: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var dateCreated: Date = Date()
    var areas: [FabArea] = []
    var fittings: [FabFitting] = []
    func area(for fitting: FabFitting) -> FabArea? { areas.first { $0.id == fitting.areaID } }
    func fittings(in areaID: UUID?) -> [FabFitting] { fittings.filter { $0.areaID == areaID } }
}

final class FabStore: ObservableObject {
    @Published private(set) var jobs: [FabJob] = []
    @Published var saveError: String? = nil
    private let fileName = "ProMetalsFab-v1-jobs.json"
    init() { load() }
    private var fileURL: URL? {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return folder.appendingPathComponent(fileName)
    }
    func load() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do { jobs = try JSONDecoder().decode([FabJob].self, from: Data(contentsOf: url)) }
        catch { saveError = "Could not load saved jobs: \(error.localizedDescription)" }
    }
    func save() {
        guard let url = fileURL else { saveError = "Documents folder is unavailable."; return }
        do { try JSONEncoder().encode(jobs).write(to: url, options: .atomic); saveError = nil }
        catch { saveError = "Could not save jobs: \(error.localizedDescription)" }
    }
    func createJob(_ name: String) -> UUID {
        let job = FabJob(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        jobs.append(job); save(); return job.id
    }
    func replace(_ job: FabJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job; save()
    }
    func removeJob(_ id: UUID) { jobs.removeAll { $0.id == id }; save() }
    func job(_ id: UUID) -> FabJob? { jobs.first { $0.id == id } }
}

func fabInches(_ value: Double) -> String {
    guard value.isFinite else { return "—" }
    return String(format: "%g\"", value)
}
