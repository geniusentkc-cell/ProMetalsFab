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
        let title = f.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? f.shape.rawValue : f.name
        drawText("ITEM \(index)  ·  \(title)", x: leftX, y: rect.minY + 7, w: 250, size: 10, bold: true)
        drawText(f.shape.rawValue + "  ·  " + (area?.name ?? "Job Root"), x: leftX, y: rect.minY + 23, w: 248, size: 8, color: .darkGray)
        drawText("TOP / PLAN", x: leftX + 9, y: rect.minY + 40, w: 112, size: 7, bold: true, color: .darkGray, align: .center)
        drawText("SIDE / ELEVATION", x: leftX + 133, y: rect.minY + 40, w: 112, size: 7, bold: true, color: .darkGray, align: .center)
        drawAssembly(f, origin: CGPoint(x: leftX + 10, y: rect.minY + 54), width: 112, height: 77, plan: true)
        drawAssembly(f, origin: CGPoint(x: leftX + 134, y: rect.minY + 54), width: 112, height: 77, plan: false)
        drawText("Entered dimensions · no insulation allowance", x: leftX, y: rect.maxY - 16, w: 255, size: 7, color: .gray)

        let x = detailsX
        let w: CGFloat = 290
        let line: CGFloat = 13
        var y = rect.minY + 8
        drawText("QTY  \(f.quantity)", x: x, y: y, w: 79, size: 10, bold: true)
        drawText(f.shape.isRound ? "ROUND" : "RECTANGULAR", x: x + 85, y: y, w: w - 85, size: 9, bold: true, color: .darkGray)
        y += 18
        let inlet = f.isRound ? "Ø \(fabInches(f.inletWidth))" : "\(fabInches(f.inletWidth)) W × \(fabInches(f.inletHeight)) H"
        drawText("IN  \(inlet)", x: x, y: y, w: w, size: 9); y += line
        if f.shape.needsOutlet {
            let outlet = f.isRound || f.shape == .squareRound ? "Ø \(fabInches(f.outletWidth))" : "\(fabInches(f.outletWidth)) W × \(fabInches(f.outletHeight)) H"
            drawText("OUT  \(outlet)", x: x, y: y, w: w, size: 9); y += line
        }
        drawText("LENGTH  \(fabInches(f.length))   ·   STRAIGHT IN/OUT \(fabInches(f.straightIn)) / \(fabInches(f.straightOut))", x: x, y: y, w: w, size: 8); y += line
        if f.shape.isTransition {
            let direction = "X \(fabInches(f.offsetX))  ·  Y \(fabInches(f.offsetY))"
            drawText("OFFSET  \(direction)", x: x, y: y, w: w, size: 8); y += line
            let vertical = f.verticalAlignment == .centered ? "Centered" :
                (f.verticalAlignment.rawValue + " " + fabInches(f.verticalValue))
            let horizontal = f.horizontalAlignment == .centered ? "Centered" :
                (f.horizontalAlignment.rawValue + (f.horizontalAlignment == .centerShift ? " " + fabInches(f.horizontalValue) : ""))
            drawText("ALIGN  V: \(vertical) / H: \(horizontal)", x: x, y: y, w: w, size: 8); y += line
        } else if f.shape.isElbow {
            drawText("ELBOW  \(fabInches(f.radius)) radius · \(Int(f.angle))° · \(f.elbowPlane == .horizontal ? "Horizontal" : "Vertical")", x: x, y: y, w: w, size: 8); y += line
        } else if f.shape == .roundTee {
            drawText("BRANCH Ø \(fabInches(f.branchDiameter))  ·  \(Int(f.angle))°", x: x, y: y, w: w, size: 8); y += line
        }
        drawText("CONN  IN \(f.inletLabel())  /  OUT \(f.outletLabel())", x: x, y: y, w: w, size: 8); y += line
        if f.isRound {
            let type = f.effectiveRoundInsulation(in: area)
            let detail = type == .none ? "None" : "\(type.rawValue)  ·  \(f.effectiveRoundThickness(in: area).rawValue)"
            drawText("INSUL  \(detail)", x: x, y: y, w: w, size: 8); y += line
        } else {
            drawText("LINER  \(f.effectiveLiner(in: area).rawValue)", x: x, y: y, w: w, size: 8); y += line
        }
        if !f.notes.isEmpty {
            let maxHeight = max(CGFloat(11), rect.maxY - y - 7)
            drawText("NOTES  " + f.notes.replacingOccurrences(of: "\n", with: "  "), x: x, y: y, w: w, size: 8, color: .darkGray, maxHeight: maxHeight)
        }
    }

    private static func drawText(_ string: String, x: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat,
                                 bold: Bool = false, color: UIColor = .black, align: NSTextAlignment = .left,
                                 maxHeight: CGFloat = 30) {
        let para = NSMutableParagraphStyle(); para.alignment = align; para.lineBreakMode = .byTruncatingTail
        let attr: [NSAttributedString.Key: Any] = [
            .font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size),
            .foregroundColor: color, .paragraphStyle: para]
        (string as NSString).draw(in: CGRect(x: x, y: y, width: w, height: maxHeight), withAttributes: attr)
    }

    private static func drawAssembly(_ f: FabFitting, origin: CGPoint, width: CGFloat, height: CGFloat, plan: Bool) {
        // Coordinates: x is flow length, y is either horizontal plan or vertical elevation.
        // Outlet center shifts reflect measured offsets; representational scale is constrained
        // to the panel, so all authoritative dimensions appear in the adjacent table.
        let r = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        let stroke = UIColor(red: 0.12, green: 0.32, blue: 0.53, alpha: 1)
        stroke.setStroke()
        if f.shape.isElbow && ((f.elbowPlane == .horizontal && plan) || (f.elbowPlane == .vertical && !plan)) {
            drawElbow(in: r, angle: f.angle, stroke: stroke)
        } else if f.shape == .roundTee {
            drawTee(in: r, stroke: stroke)
        } else {
            let leftSize = plan ? f.inletWidth : (f.isRound ? f.inletWidth : f.inletHeight)
            let rightSize = f.shape.needsOutlet ? (plan ? f.outletWidth : (f.effectiveOutletHeight)) : leftSize
            let shift = plan ? f.offsetX : f.offsetY
            let maxSpan = max(leftSize, rightSize) + abs(shift) * 2
            let scale = min(2.65, 56.0 / CGFloat(max(maxSpan, 1)))
            let cy = r.midY
            let leftHalf = CGFloat(leftSize) * scale * 0.5
            let rightHalf = CGFloat(rightSize) * scale * 0.5
            // UIKit Y points down, therefore positive Y offset moves the outlet upwards.
            let rightCY = cy - CGFloat(shift) * scale
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
        let dimension = plan ? f.inletWidth : (f.isRound ? f.inletWidth : f.inletHeight)
        let outletDimension = f.shape.needsOutlet ? (plan ? f.outletWidth : f.effectiveOutletHeight) : dimension
        drawText("IN \(fabInches(dimension))  →  OUT \(fabInches(outletDimension))", x: r.minX - 2, y: r.maxY - 5, w: r.width + 4, size: 6.5, color: .darkGray, align: .center)
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
