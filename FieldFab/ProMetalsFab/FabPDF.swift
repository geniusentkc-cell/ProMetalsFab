import Foundation
import UIKit

// PDF is a four-row portrait fabrication REQUEST. Diagrams communicate the
// assembled fitting and offset direction; exact shop dimensions remain in text.
enum FabPDFExporter {
    enum ExportError: LocalizedError {
        case noFittings
        var errorDescription: String? { "No fittings have been added to this selection." }
    }
    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    static func export(job: FabJob, areaID: UUID?, includeAllAreas: Bool = false) throws -> URL {
        let selected = includeAllAreas ? job.fittings : job.fittings(in: areaID)
        guard !selected.isEmpty else { throw ExportError.noFittings }
        let areaName = includeAllAreas ? "All Areas" : (areaID.flatMap { id in job.areas.first { $0.id == id }?.name } ?? "Job Root")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = (["ProMetalsFab", job.name, areaName, formatter.string(from: Date())]
            .joined(separator: "-")
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let pages = Int(ceil(Double(selected.count) / 4.0))
        let data = renderer.pdfData { pdf in
            for pageIndex in 0..<pages {
                pdf.beginPage()
                drawHeader(job: job, areaName: areaName, pageIndex: pageIndex, pages: pages)
                for row in 0..<4 {
                    let index = pageIndex * 4 + row
                    if index >= selected.count { break }
                    let fitting = selected[index]
                    drawFitting(fitting, index: index + 1, area: job.area(for: fitting),
                                rect: CGRect(x: 24, y: 77 + CGFloat(row) * 163.5, width: 564, height: 158))
                }
                drawFooter(page: pageIndex + 1, total: pages)
            }
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func drawHeader(job: FabJob, areaName: String, pageIndex: Int, pages: Int) {
        UIColor(red: 0.09, green: 0.19, blue: 0.31, alpha: 1).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 612, height: 62))
        drawText("PRO METALS  /  FABRICATION REQUEST", x: 24, y: 13, w: 445, size: 14, bold: true, color: .white)
        drawText(job.name, x: 24, y: 34, w: 310, size: 10, color: .white)
        drawText(areaName, x: 344, y: 34, w: 245, size: 10, color: .white, align: .right)
        drawText("\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))  •  Page \(pageIndex + 1) / \(pages)",
                 x: 382, y: 14, w: 207, size: 9, color: .white, align: .right)
        drawText("Four fittings per page  ·  Finished dimensions in inches", x: 24, y: 64, w: 560, size: 8, color: .darkGray)
    }
    private static func drawFooter(page: Int, total: Int) {
        UIColor.lightGray.setStroke()
        let line = UIBezierPath(); line.move(to: CGPoint(x: 24, y: 746)); line.addLine(to: CGPoint(x: 588, y: 746)); line.stroke()
        drawText("ASSEMBLY SCHEMATICS — NOT TO SCALE. NO FLAT PATTERNS. Verify dimensions before fabrication.",
                 x: 24, y: 750, w: 520, size: 7, color: .darkGray)
        drawText("\(page) / \(total)", x: 545, y: 750, w: 43, size: 7, align: .right)
    }
    private static func drawFitting(_ f: FabFitting, index: Int, area: FabArea?, rect: CGRect) {
        UIColor(red: 0.80, green: 0.84, blue: 0.89, alpha: 1).setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 5)
        border.lineWidth = 0.8; border.stroke()
        let leftX = rect.minX + 10
        let detailsX = rect.minX + 284
        UIColor(red: 0.95, green: 0.97, blue: 0.985, alpha: 1).setFill()
        UIRectFill(CGRect(x: rect.minX + 1, y: rect.minY + 1, width: 272, height: rect.height - 2))
        let divider = UIBezierPath()
        divider.move(to: CGPoint(x: rect.minX + 274, y: rect.minY + 6))
        divider.addLine(to: CGPoint(x: rect.minX + 274, y: rect.maxY - 6))
        divider.lineWidth = 0.8; UIColor.lightGray.setStroke(); divider.stroke()
        let title = f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? f.shape.displayName : f.name
        drawText("ITEM \(index)  ·  \(title)", x: leftX, y: rect.minY + 7, w: 250, size: 10, bold: true)
        drawText(f.shape.displayName + "  ·  " + (area?.name ?? "Job Root"), x: leftX, y: rect.minY + 23, w: 248, size: 8, color: .darkGray)
        if f.shape.isCatalogRect {
            let images = FabDiagramArt.images(for: f)
            drawText(f.shape == .rectTransition ? "LIVE TRANSITION VIEWS" : "APPROVED FITTING REFERENCE",
                     x: leftX + 2, y: rect.minY + 39, w: 260, size: 7,
                     bold: true, color: .darkGray, align: .center)
            let imageBox = CGRect(x: leftX + 5, y: rect.minY + 51, width: 248, height: 82)
            if images.isEmpty {
                drawText("Missing diagram asset", x: imageBox.minX, y: imageBox.midY,
                         w: imageBox.width, size: 8, color: .red, align: .center)
            } else {
                let gap: CGFloat = images.count > 1 ? 4 : 0
                let cellW = (imageBox.width - gap * CGFloat(images.count - 1)) / CGFloat(images.count)
                for (i, image) in images.enumerated() {
                    let cell = CGRect(x: imageBox.minX + CGFloat(i) * (cellW + gap),
                                      y: imageBox.minY, width: cellW, height: imageBox.height)
                    drawFittedImage(image, within: cell)
                }
            }
        } else {
            let isElbow = f.shape.isElbow
            drawText(isElbow ? "BEND / SCHEMATIC" : "TOP / PLAN", x: leftX + 9, y: rect.minY + 40, w: 112, size: 7, bold: true, color: .darkGray, align: .center)
            drawText(isElbow ? "END / SECTION" : "SIDE / ELEVATION", x: leftX + 133, y: rect.minY + 40, w: 112, size: 7, bold: true, color: .darkGray, align: .center)
            drawAssembly(f, origin: CGPoint(x: leftX + 10, y: rect.minY + 54), width: 112, height: 77, plan: true)
            drawAssembly(f, origin: CGPoint(x: leftX + 134, y: rect.minY + 54), width: 112, height: 77, plan: false)
        }
        drawText("Entered dimensions · no insulation allowance", x: leftX, y: rect.maxY - 16, w: 255, size: 7, color: .gray)

        let x = detailsX
        let w: CGFloat = 270
        var y = rect.minY + 8
        drawText("QTY  \(f.quantity)", x: x, y: y, w: 80, size: 10, bold: true)
        drawText(f.shape.isCustom ? "SPECIAL REQUEST" : (f.isRound ? "ROUND" : "RECTANGULAR"),
                 x: x + 87, y: y, w: w - 87, size: 9, bold: true, color: .darkGray)
        y += 19
        var details: [String] = []
        if f.shape.isCatalogRect {
            switch f.shape {
            case .rectEndCap:
                details.append("A WIDTH \(fabInches(f.inletWidth))  ·  B DEPTH \(fabInches(f.inletHeight))")
                details.append("CONNECTION  \(f.inletLabel())")
            case .rectTee:
                details.append("A×B BOTTOM  \(fabInches(f.inletWidth)) × \(fabInches(f.inletHeight))")
                details.append("C×D LEFT  \(fabInches(f.outletWidth)) × \(fabInches(f.outletHeight))")
                details.append("E×F RIGHT  \(fabInches(f.teeE)) × \(fabInches(f.teeF))")
                details.append("THROATS  G \(fabInches(f.teeG)) · H \(fabInches(f.teeH))")
                details.append("THROATS  I \(fabInches(f.teeI)) · J \(fabInches(f.teeJ))")
                details.append("CONN BOTTOM  \(f.inletLabel())")
                details.append("CONN LEFT  \(f.outletLabel())")
                details.append("CONN RIGHT  \(f.teeRightLabel())")
            case .squareRound:
                details.append("A WIDTH \(fabInches(f.inletWidth)) · B DEPTH \(fabInches(f.inletHeight))")
                details.append("C ROUND DIA \(fabInches(f.outletWidth)) · D LENGTH \(fabInches(f.length))")
                details.append("RECT CONN  \(f.inletLabel())")
                details.append("ROUND CONN  \(f.outletLabel())")
                details.append("DAMPER  \(f.isDampered ? "YES" : "NO")")
            default:
                details.append("A WIDTH IN \(fabInches(f.inletWidth)) · B DEPTH IN \(fabInches(f.inletHeight))")
                let w = f.shape == .rectStraight ? f.inletWidth : f.outletWidth
                let d = f.shape == .rectStraight ? f.inletHeight : f.outletHeight
                details.append("C WIDTH OUT \(fabInches(w)) · D DEPTH OUT \(fabInches(d))")
                if f.shape.isSquareElbow {
                    details.append("E THROAT 1 \(fabInches(f.straightIn)) · F THROAT 2 \(fabInches(f.straightOut))")
                } else if f.shape == .rectRadiusElbow {
                    details.append("E INTERIOR RADIUS \(fabInches(f.radius))")
                    let s: Double = f.verticalValue
                    let direction: String = s < 0.0 ? "DOWN" : "UP"
                    let magnitude: Double = Swift.abs(s)
                    let offsetDescription: String = fabInches(magnitude)
                    details.append("F TOP \(direction) \(offsetDescription) (both sides)")
                } else if f.shape == .rectTransition {
                    details.append("LENGTH \(fabInches(f.length)) · STR IN/OUT \(fabInches(f.straightIn))/\(fabInches(f.straightOut))")
                    details.append("LEFT \(fabInches(f.transitionLeft)) · RIGHT \(fabInches(f.transitionRight))")
                    details.append("TOP \(fabInches(f.transitionTop)) · BOTTOM \(fabInches(f.transitionBottom))")
                } else {
                    details.append("E LENGTH \(fabInches(f.length))")
                }
                details.append("CONN IN \(f.inletLabel()) / OUT \(f.outletLabel())")
            }
            details.append("LINER \(f.effectiveLiner(in: area).rawValue)")
        } else if !f.shape.isCustom {
            if f.isRound {
                let diaOut = f.shape.isRoundElbow || f.shape == .roundStraight ? f.inletWidth : f.outletWidth
                details.append("A DIA IN \(fabInches(f.inletWidth)) · C DIA OUT \(fabInches(diaOut))")
            } else {
                details.append("A WI \(fabInches(f.inletWidth)) · B DI \(fabInches(f.inletHeight))")
                details.append("C WO \(fabInches(f.outletWidth)) · D DO \(fabInches(f.outletHeight))")
            }
            if f.shape.isRoundElbow {
                details.append("J ELBOW ANGLE \(f.shape == .roundElbow45 ? "45°" : "90°")")
            } else {
                details.append("E LENGTH \(fabInches(f.length))")
                details.append("K STR IN \(fabInches(f.straightIn)) · L STR OUT \(fabInches(f.straightOut))")
            }
            if f.shape.isTransition {
                details.append("F X SHIFT \(fabInches(f.offsetX)) · G Y SHIFT \(fabInches(f.offsetY))")
            }
            if f.shape == .roundTee {
                details.append("M BRANCH DIA \(fabInches(f.branchDiameter)) · J ANGLE \(Int(f.angle))°")
            }
            details.append("CONN IN \(f.inletLabel()) / OUT \(f.outletLabel())")
            if f.isRound {
                let type = f.effectiveRoundInsulation(in: area)
                details.append("INSUL " + (type == .none ? "None" : "\(type.rawValue) \(f.effectiveRoundThickness(in: area).rawValue)"))
            } else {
                details.append("LINER \(f.effectiveLiner(in: area).rawValue)")
            }
        } else {
            details.append("Refer to written custom fitting instructions")
        }
        for detail in details {
            if y > rect.maxY - 12 { break }
            let dense = f.shape == .rectTee
            drawText(detail, x: x, y: y, w: w, size: dense ? 7.0 : 7.7, maxHeight: dense ? 11 : 12)
            y += dense ? 11 : 12
        }
        if !f.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let space = rect.maxY - y - 5
            if space > 8 {
                drawText("NOTES  " + f.notes.replacingOccurrences(of: "\n", with: "  "),
                         x: x, y: y, w: w, size: 7.5, color: .darkGray,
                         maxHeight: space, wrap: true)
            }
        }
    }

    private static func drawText(_ string: String, x: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat,
                                 bold: Bool = false, color: UIColor = .black, align: NSTextAlignment = .left,
                                 maxHeight: CGFloat = 30, wrap: Bool = false) {
        let para = NSMutableParagraphStyle(); para.alignment = align
        para.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        let attr: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
            .foregroundColor: color, .paragraphStyle: para]
        (string as NSString).draw(in: CGRect(x: x, y: y, width: w, height: maxHeight), withAttributes: attr)
    }

    private static func drawFittedImage(_ image: UIImage, within rect: CGRect) {
        let sz = image.size
        guard sz.width > 0, sz.height > 0 else { return }
        let factor = min(rect.width / sz.width, rect.height / sz.height)
        let dw = sz.width * factor, dh = sz.height * factor
        image.draw(in: CGRect(x: rect.midX - dw/2, y: rect.midY - dh/2, width: dw, height: dh))
    }

    private static func drawAssembly(_ f: FabFitting, origin: CGPoint, width: CGFloat, height: CGFloat, plan: Bool) {
        // Coordinates: x is flow length, y is either horizontal plan or vertical elevation.
        // Outlet center shifts reflect measured offsets; representational scale is constrained
        // to the panel, so all authoritative dimensions appear in the adjacent table.
        let r = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        let stroke = UIColor(red: 0.12, green: 0.32, blue: 0.53, alpha: 1)
        stroke.setStroke()
        if f.shape.isCustom {
            drawText("CUSTOM FITTING", x: r.minX, y: r.midY - 7, w: r.width, size: 8,
                     bold: true, color: .darkGray, align: .center)
            return
        }
        if f.shape.isElbow && plan {
            if f.shape.isRectElbow {
                drawRectElbow(in: r, angle: f.angle, throatIn: f.straightIn,
                              throatOut: f.straightOut, stroke: stroke)
            } else {
                drawElbow(in: r, angle: f.shape == .roundElbow45 ? 45 : 90, stroke: stroke)
            }
        } else if f.shape == .roundTee {
            drawTee(in: r, stroke: stroke)
        } else {
            let leftSize: Double = plan ? f.inletWidth : (f.isRound ? f.inletWidth : f.inletHeight)
            let rightSize: Double = f.shape.needsOutlet ? (plan ? f.outletWidth : (f.effectiveOutletHeight)) : leftSize
            let shift: Double = f.shape.isElbow ? 0 : (plan ? f.offsetX : f.offsetY)
            let maxSpan: Double = Swift.max(leftSize, rightSize) + Swift.abs(shift) * 2.0
            let scale: CGFloat = Swift.min(CGFloat(2.65), CGFloat(56.0) / CGFloat(Swift.max(maxSpan, 1.0)))
            let cy = r.midY
            let leftHalf: CGFloat = CGFloat(leftSize) * scale * 0.5
            let rightHalf: CGFloat = CGFloat(rightSize) * scale * 0.5
            // UIKit Y points down, therefore positive Y offset moves the outlet upwards.
            let rightCY: CGFloat = cy - CGFloat(shift) * scale
            let x1 = r.minX + 7, x2 = r.minX + 25, x3 = r.maxX - 25, x4 = r.maxX - 7
            let top = UIBezierPath()
            top.move(to: CGPoint(x: x1, y: cy - leftHalf))
            top.addLine(to: CGPoint(x: x2, y: cy - leftHalf))
            top.addLine(to: CGPoint(x: x3, y: rightCY - rightHalf))
            top.addLine(to: CGPoint(x: x4, y: rightCY - rightHalf))
            top.move(to: CGPoint(x: x1, y: cy + leftHalf))
            top.addLine(to: CGPoint(x: x2, y: cy + leftHalf))
            top.addLine(to: CGPoint(x: x3, y: rightCY + rightHalf))
            top.addLine(to: CGPoint(x: x4, y: rightCY + rightHalf))
            top.move(to: CGPoint(x: x1, y: cy - leftHalf))
            top.addLine(to: CGPoint(x: x1, y: cy + leftHalf))
            top.move(to: CGPoint(x: x4, y: rightCY - rightHalf))
            top.addLine(to: CGPoint(x: x4, y: rightCY + rightHalf))
            top.lineWidth = 1.45; top.stroke()
            let axis = UIBezierPath()
            axis.move(to: CGPoint(x: x1 - 2, y: cy)); axis.addLine(to: CGPoint(x: x4 + 2, y: rightCY))
            axis.lineWidth = 0.4; axis.setLineDash([3, 3], count: 2, phase: 0); UIColor.gray.setStroke(); axis.stroke()
            stroke.setStroke()
        }
        let leftKey = plan ? "A" : (f.isRound ? "A" : "B")
        let rightKey = plan ? "C" : (f.isRound ? "C" : "D")
        let initial = plan || f.isRound ? f.inletWidth : f.inletHeight
        let final: Double
        if f.shape.isRoundElbow || f.shape.isRectElbow || f.shape.isStraight {
            final = initial
        } else if f.shape.needsOutlet {
            final = plan ? f.outletWidth : f.effectiveOutletHeight
        } else {
            final = initial
        }
        drawText("\(leftKey) \(fabInches(initial))  →  \(rightKey) \(fabInches(final))",
                 x: r.minX - 2, y: r.maxY - 5, w: r.width + 4,
                 size: 6.5, color: .darkGray, align: .center)
    }
    private static func drawRectElbow(in rect: CGRect, angle: Double,
                                      throatIn: Double, throatOut: Double, stroke: UIColor) {
        let path = UIBezierPath()
        if angle < 70 {
            path.move(to: CGPoint(x: rect.minX + 12, y: rect.maxY - 14))
            path.addLine(to: CGPoint(x: rect.minX + 12, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX + 6, y: rect.minY + 5))
            path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.midY - 3))
            path.addLine(to: CGPoint(x: rect.midX + 20, y: rect.maxY - 14))
        } else {
            path.move(to: CGPoint(x: rect.minX + 13, y: rect.maxY - 10))
            path.addLine(to: CGPoint(x: rect.minX + 13, y: rect.minY + 7))
            path.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.minY + 7))
            path.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.maxY - 10))
            path.addLine(to: CGPoint(x: rect.minX + 13, y: rect.maxY - 10))
            // Turning-vane strokes visually distinguish the mitered elbow schematic.
            for index in 0..<5 {
                let shift = CGFloat(index) * 10
                path.move(to: CGPoint(x: rect.minX + 19 + shift, y: rect.maxY - 16 - shift * 0.6))
                path.addQuadCurve(to: CGPoint(x: rect.minX + 32 + shift, y: rect.maxY - 18 - shift * 0.6),
                                  controlPoint: CGPoint(x: rect.minX + 22 + shift, y: rect.maxY - 5 - shift * 0.6))
            }
        }
        path.lineWidth = 1.4
        stroke.setStroke(); path.stroke()
        drawText("K \(fabInches(throatIn))", x: rect.minX + 7, y: rect.minY, w: 54,
                 size: 6.5, color: .darkGray)
        drawText("L \(fabInches(throatOut))", x: rect.maxX - 62, y: rect.maxY - 14,
                 w: 62, size: 6.5, color: .darkGray, align: .right)
    }
    private static func drawElbow(in rect: CGRect, angle: Double, stroke: UIColor) {
        if angle < 70 {
            // A 45-degree assembled elbow, shown in its selected bending plane.
            let upper = UIBezierPath()
            upper.move(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 37))
            upper.addLine(to: CGPoint(x: rect.minX + 53, y: rect.maxY - 37))
            upper.addQuadCurve(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 14), controlPoint: CGPoint(x: rect.minX + 66, y: rect.maxY - 37))
            upper.move(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 18))
            upper.addLine(to: CGPoint(x: rect.minX + 53, y: rect.maxY - 18))
            upper.addQuadCurve(to: CGPoint(x: rect.maxX - 20, y: rect.minY + 8), controlPoint: CGPoint(x: rect.minX + 71, y: rect.maxY - 18))
            upper.lineWidth = 1.6; stroke.setStroke(); upper.stroke()
            return
        }
        let p = UIBezierPath()
        p.move(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 19))
        p.addLine(to: CGPoint(x: rect.minX + 56, y: rect.maxY - 19))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 19, y: rect.minY + 12), controlPoint: CGPoint(x: rect.maxX - 19, y: rect.maxY - 19))
        p.addLine(to: CGPoint(x: rect.maxX - 19, y: rect.minY + 4))
        p.move(to: CGPoint(x: rect.minX + 7, y: rect.maxY - 38))
        p.addLine(to: CGPoint(x: rect.minX + 56, y: rect.maxY - 38))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 38, y: rect.minY + 12), controlPoint: CGPoint(x: rect.maxX - 38, y: rect.maxY - 38))
        p.addLine(to: CGPoint(x: rect.maxX - 38, y: rect.minY + 4))
        p.lineWidth = 1.6; stroke.setStroke(); p.stroke()
    }
    private static func drawTee(in rect: CGRect, stroke: UIColor) {
        let p = UIBezierPath()
        let y = rect.midY
        p.move(to: CGPoint(x: rect.minX + 7, y: y - 13)); p.addLine(to: CGPoint(x: rect.maxX - 7, y: y - 13))
        p.move(to: CGPoint(x: rect.minX + 7, y: y + 13)); p.addLine(to: CGPoint(x: rect.maxX - 7, y: y + 13))
        p.move(to: CGPoint(x: rect.midX - 12, y: y - 13)); p.addLine(to: CGPoint(x: rect.midX - 12, y: rect.minY + 3))
        p.move(to: CGPoint(x: rect.midX + 12, y: y - 13)); p.addLine(to: CGPoint(x: rect.midX + 12, y: rect.minY + 3))
        p.lineWidth = 1.6; stroke.setStroke(); p.stroke()
    }
}

// Both the editor and PDF call this one image provider. Only RECT-004 transitions
// are calculated dynamically. All other V3 rectangular fitting images are fixed
// high-resolution black-on-white conversions of the approved AutoCAD screenshots.
enum FabDiagramArt {
    static func images(for f: FabFitting) -> [UIImage] {
        if f.shape == .rectTransition {
            return [transition(f, plan: true), transition(f, plan: false)]
        }
        let names: [String]
        switch f.shape {
        case .rectElbow45: names = ["FabRect45"]
        case .rectElbow90: names = ["FabRect90Front", "FabRect90Side"]
        case .rectStraight: names = ["FabRectStraightEnd", "FabRectStraightSide"]
        case .rectRadiusElbow: names = ["FabRectRadiusEnd", "FabRectRadiusSide"]
        case .rectTee: names = ["FabRectTee"]
        case .squareRound: names = ["FabSquareRoundEnd", "FabSquareRoundSide"]
        case .rectEndCap: names = ["FabRectEndCap"]
        default: names = []
        }
        return names.compactMap { UIImage(named: $0) }
    }

    private static func transition(_ f: FabFitting, plan: Bool) -> UIImage {
        let size = CGSize(width: 480, height: 300)
        let axisIn = max(0.01, (plan ? f.inletWidth : f.inletHeight).isFinite ? (plan ? f.inletWidth : f.inletHeight) : 0.01)
        let axisOut = max(0.01, (plan ? f.outletWidth : f.outletHeight).isFinite ? (plan ? f.outletWidth : f.outletHeight) : 0.01)
        let unverifiedShift = plan ? f.offsetX : f.offsetY // positive = right/up
        let shift = unverifiedShift.isFinite ? unverifiedShift : 0
        let v0 = -axisIn / 2, v1 = axisIn / 2
        let v2 = -shift - axisOut / 2, v3 = -shift + axisOut / 2
        let lo = min(v0, v2), hi = max(v1, v3)
        let scale = min(6.5, 188 / max(hi - lo, 0.1))
        let padTop: CGFloat = 37
        let y0 = padTop + CGFloat((v0 - lo) * scale)
        let y1 = padTop + CGFloat((v1 - lo) * scale)
        let y2 = padTop + CGFloat((v2 - lo) * scale)
        let y3 = padTop + CGFloat((v3 - lo) * scale)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            renderer.cgContext.setFillColor(UIColor.white.cgColor)
            renderer.cgContext.fill(CGRect(origin: .zero, size: size))
            // Length affects the apparent run of the schematic; the throat side values
            // are independently dimensioned and displayed numerically in the PDF.
            let nominalRun = f.length.isFinite ? max(0, f.length) : 24
            let run = CGFloat(min(280, max(100, nominalRun * 9)))
            let x2: CGFloat = 239 - run/2
            let x3: CGFloat = 239 + run/2
            let x1: CGFloat = x2 - 22
            let x4: CGFloat = x3 + 22
            let p = UIBezierPath()
            p.lineWidth = 3; UIColor.black.setStroke()
            p.move(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x2, y: y0))
            p.addLine(to: CGPoint(x: x3, y: y2)); p.addLine(to: CGPoint(x: x4, y: y2))
            p.move(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x2, y: y1))
            p.addLine(to: CGPoint(x: x3, y: y3)); p.addLine(to: CGPoint(x: x4, y: y3))
            p.move(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1))
            p.move(to: CGPoint(x: x4, y: y2)); p.addLine(to: CGPoint(x: x4, y: y3))
            p.stroke()
            let centerLine = UIBezierPath()
            centerLine.move(to: CGPoint(x: x1, y: (y0+y1)/2))
            centerLine.addLine(to: CGPoint(x: x4, y: (y2+y3)/2))
            centerLine.lineWidth = 1.25; centerLine.setLineDash([8, 6], count: 2, phase: 0)
            UIColor.gray.setStroke(); centerLine.stroke()
            func text(_ content: String, _ box: CGRect, size: CGFloat = 20) {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
                (content as NSString).draw(in: box, withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: .medium),
                    .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
            }
            text(plan ? "A (WIDTH IN)" : "B (DEPTH IN)", CGRect(x: 0, y: 255, width: 225, height: 35), size: 18)
            text(plan ? "C (WIDTH OUT)" : "D (DEPTH OUT)", CGRect(x: 245, y: 255, width: 235, height: 35), size: 18)
            text(plan ? "PLAN — LEFT / RIGHT" : "ELEVATION — TOP / BOTTOM", CGRect(x: 52, y: 3, width: 380, height: 30), size: 18)
        }
    }
}
