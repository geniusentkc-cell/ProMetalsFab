import Foundation

import Combine
// ProMetalsFab V1 uses inches throughout. Entered finished dimensions are NEVER
// changed to compensate for liner or insulation. PractiCAM handles allowances.
enum FabShape: String, Codable, CaseIterable, Identifiable {
    case rectStraight = "Rectangular Straight"
    case rectTransition = "Rectangular Transition"
    case rectElbow45 = "Rectangular 45° Elbow"
    case rectElbow90 = "Rectangular 90° Elbow"
    case rectOffset = "Rectangular Offset"
    case squareRound = "Square to Round"
    case roundStraight = "Round Straight"
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
    static var libraryChoices: [FabShape] { allCases.filter { $0 != .roundElbow45 } }
    var displayName: String { isRoundElbow ? "Round Elbow" : rawValue }
    var isRectElbow: Bool { self == .rectElbow45 || self == .rectElbow90 }
    var isRoundElbow: Bool { self == .roundElbow45 || self == .roundElbow90 }
    var isStraight: Bool { self == .rectStraight || self == .roundStraight }
    var isCustom: Bool { self == .custom }
    var isRound: Bool {
        switch self {
        case .roundStraight, .roundReducer, .roundEccentric, .roundElbow45,
             .roundElbow90, .roundOffset, .roundTee: return true
        default: return false
        }
    }
    var isTransition: Bool { self == .rectTransition || self == .rectOffset || self == .squareRound || self == .roundReducer || self == .roundEccentric || self == .roundOffset }
    var isElbow: Bool { self == .rectElbow45 || self == .rectElbow90 || self == .roundElbow45 || self == .roundElbow90 }
    var needsOutlet: Bool { isTransition || self == .roundTee }
}

enum FabConnection: String, Codable, CaseIterable, Identifiable {
    case slipDrive = "S&D", driveSlip = "D&S", tdf = "TDF", special = "Special"
    // Older names are retained so V1 saved jobs remain decodable.
    case plain = "Plain", beaded = "Beaded", flanged = "Flanged"
    case raw = "Raw", bead = "Bead", custom = "Custom"
    var id: String { rawValue }
    static var rectangular: [FabConnection] { [.slipDrive, .driveSlip, .tdf, .special] }
    static var round: [FabConnection] { [.raw, .bead, .custom] }
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

struct FabArea: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rectangularLiner: FabLiner = .none
    var roundInsulation: FabRoundInsulation = .none
    var roundThickness: FabThickness = .one
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
    var notes: String = ""

    var isRound: Bool { shape.isRound }
    var effectiveOutletHeight: Double {
        (shape.isRound || shape == .squareRound) ? outletWidth : outletHeight
    }
    func effectiveLiner(in area: FabArea?) -> FabLiner { linerOverride ?? area?.rectangularLiner ?? .none }
    func effectiveRoundInsulation(in area: FabArea?) -> FabRoundInsulation { roundInsulationOverride ?? area?.roundInsulation ?? .none }
    func effectiveRoundThickness(in area: FabArea?) -> FabThickness { roundThicknessOverride ?? area?.roundThickness ?? .one }
    var effectiveOutletWidth: Double { shape.isRoundElbow || shape.isStraight || shape.isRectElbow ? inletWidth : outletWidth }
    var effectiveOutletDepth: Double { shape.isRoundElbow || shape.isStraight || shape.isRectElbow ? inletHeight : outletHeight }
    private func connectionLabel(_ connection: FabConnection, description: String) -> String {
        let selected = isRound ? connection.normalizedRound : connection
        if selected == .special || selected == .custom {
            return "Custom: " + (description.isEmpty ? "Unspecified" : description)
        }
        return selected.rawValue
    }
    func inletLabel() -> String { connectionLabel(inletConnection, description: inletSpecial) }
    func outletLabel() -> String { connectionLabel(outletConnection, description: outletSpecial) }
    var dimensionLegend: String {
        if shape.isCustom { return "Describe custom fitting in Notes" }
        if shape.isRoundElbow { return "A Diameter In = C Diameter Out · J Angle" }
        if shape.isRound { return "A Diameter In · C Diameter Out · E Length" }
        if shape.isRectElbow { return "A/B In · C/D Out · K/L Throat Straights" }
        return "A Width In · B Depth In · C Width Out · D Depth Out · E Length"
    }

    // Center displacement of the outlet, relative to inlet, in finished inches.
    // Positive Y is up; a Top Down value of 2 lowers the outlet's top by 2.
    var offsetY: Double {
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
        if shape.isCustom {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Describe the custom fitting in Shop Notes." : nil
        }
        let values = [inletWidth, inletHeight, outletWidth, outletHeight, length,
                      straightIn, straightOut, angle, radius, branchDiameter,
                      verticalValue, horizontalValue]
        guard values.allSatisfy({ $0.isFinite }) else { return "Measurements must be valid finite numbers." }
        guard inletWidth > 0, (!shape.isRound && inletHeight > 0 || shape.isRound) else {
            return "Inlet dimensions must be greater than zero."
        }
        if !shape.isElbow && length <= 0 { return "Length must be greater than zero." }
        if shape.needsOutlet && (outletWidth <= 0 || (!shape.isRound && shape != .squareRound && outletHeight <= 0)) {
            return "Outlet dimensions must be greater than zero."
        }
        if shape.isRectElbow && (straightIn < 0 || straightOut < 0) {
            return "Throat straight lengths cannot be negative."
        }
        if !shape.isElbow && !shape.isStraight && (straightIn < 0 || straightOut < 0 || straightIn + straightOut > length) {
            return "Straight-in plus straight-out must not exceed overall length."
        }
        if shape == .roundTee && branchDiameter <= 0 { return "Branch diameter must be greater than zero." }
        if shape.isRound && (inletConnection.normalizedRound == .custom && inletSpecial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                             outletConnection.normalizedRound == .custom && outletSpecial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return "Enter the description for each Custom round connection."
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
        if shape.isRoundElbow {
            fitting.outletWidth = fitting.inletWidth; fitting.outletHeight = fitting.inletHeight
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
