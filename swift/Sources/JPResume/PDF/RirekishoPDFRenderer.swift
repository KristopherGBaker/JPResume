import AppKit
import CoreGraphics
import CoreText
import Foundation

enum RirekishoPDFRenderer {
    // A4 in points: 210mm × 297mm
    private static let pageW: CGFloat = 595.27
    private static let pageH: CGFloat = 841.89
    private static let margin: CGFloat = 28.35 // 10mm

    private static let contentW: CGFloat = 595.27 - 2 * 28.35 // ~538.57

    // Photo
    private static let photoW: CGFloat = 85.04 // 30mm
    private static let photoH: CGFloat = 113.39 // 40mm

    // Table columns
    private static let yearW: CGFloat = 51.02 // 18mm
    private static let monthW: CGFloat = 34.02 // 12mm
    private static var descW: CGFloat { contentW - yearW - monthW }

    // Row heights
    private static let rowH: CGFloat = 15.59 // 5.5mm
    private static let smallH: CGFloat = 14.17 // 5mm

    static func render(data: RirekishoData, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PDFError.cannotCreate
        }
        ctx.beginPage(mediaBox: &mediaBox)
        draw(data: data, in: ctx, mediaBox: &mediaBox)
        ctx.endPage()
        ctx.closePDF()
    }

    /// Start a new page and reset y to the top
    private static func newPageIfNeeded(_ y: inout CGFloat, needed: CGFloat,
                                        ctx: CGContext, mediaBox: inout CGRect) {
        if y - needed < margin {
            ctx.endPage()
            ctx.beginPage(mediaBox: &mediaBox)
            y = pageH - margin
        }
    }

    private static func draw(data: RirekishoData, in ctx: CGContext, mediaBox: inout CGRect) {
        let x0 = margin
        var y = pageH - margin // Start from top

        // ===== TITLE =====
        let titleFont = PDFFont.japaneseBold(size: 16)
        drawText("履 歴 書", at: CGPoint(x: x0, y: y - 14), font: titleFont, in: ctx)
        let dateFont = PDFFont.japanese(size: 8)
        drawTextRight(data.creationDate, at: CGPoint(x: x0 + contentW, y: y - 10), font: dateFont, in: ctx)
        y -= 18

        // ===== PERSONAL INFO =====
        let infoW = contentW - photoW - 5.67 // 2mm gap
        let labelW: CGFloat = 62.36 // 22mm

        // Furigana row
        let furiH: CGFloat = 14.17 // 5mm
        drawLabelRow(ctx: ctx, x: x0, y: y, w: infoW, h: furiH,
                     labelW: labelW, label: "ふりがな", value: data.nameFurigana,
                     labelSize: 6, valueSize: 6)
        y -= furiH

        // Name row
        let nameH: CGFloat = 34.02 // 12mm
        drawLabelRow(ctx: ctx, x: x0, y: y, w: infoW, h: nameH,
                     labelW: labelW, label: "氏　名", value: data.nameKanji,
                     labelSize: 7, valueSize: 14)
        y -= nameH

        // DOB / Gender row
        let dobH: CGFloat = 19.84 // 7mm
        drawBox(ctx: ctx, x: x0, y: y, w: infoW, h: dobH)
        var dobText = "生年月日　\(data.dateOfBirth)"
        if let gender = data.gender {
            dobText += "　　　　性別　\(gender)"
        }
        drawText(dobText, at: CGPoint(x: x0 + 5.67, y: y - dobH / 2 - 2.5),
                 font: PDFFont.japanese(size: 7), in: ctx)
        y -= dobH

        // Photo box (spans all three rows above)
        let photoX = x0 + infoW + 5.67
        let photoTop = y + furiH + nameH + dobH
        let photoTotalH = furiH + nameH + dobH
        drawBox(ctx: ctx, x: photoX, y: photoTop, w: photoW, h: photoTotalH)
        drawTextCentered("写真", at: CGPoint(x: photoX + photoW / 2, y: photoTop - photoTotalH / 2 + 4),
                         font: PDFFont.japanese(size: 7), in: ctx)
        drawTextCentered("(3×4cm)", at: CGPoint(x: photoX + photoW / 2, y: photoTop - photoTotalH / 2 - 8),
                         font: PDFFont.japanese(size: 5), in: ctx)

        // ===== ADDRESS =====
        // Address furigana
        let addrFuriH = smallH
        let postal = data.postalCode.map { "〒\($0)　" } ?? ""
        drawLabelRow(ctx: ctx, x: x0, y: y, w: contentW, h: addrFuriH,
                     labelW: labelW, label: "ふりがな", value: postal + (data.addressFurigana ?? ""),
                     labelSize: 6, valueSize: 5)
        y -= addrFuriH

        // Address
        let addrH: CGFloat = 28.35 // 10mm
        drawLabelRow(ctx: ctx, x: x0, y: y, w: contentW, h: addrH,
                     labelW: labelW, label: "現住所", value: data.address ?? "",
                     labelSize: 7, valueSize: 8)
        y -= addrH

        // Phone / Email
        let contactH: CGFloat = 19.84 // 7mm
        let halfW = contentW / 2
        let telLblW: CGFloat = 45.35 // 16mm
        drawLabelRow(ctx: ctx, x: x0, y: y, w: halfW, h: contactH,
                     labelW: telLblW, label: "電話", value: data.phone ?? "",
                     labelSize: 6, valueSize: 8)
        drawLabelRow(ctx: ctx, x: x0 + halfW, y: y, w: halfW, h: contactH,
                     labelW: telLblW, label: "E-mail", value: data.email ?? "",
                     labelSize: 6, valueSize: 7)
        y -= contactH

        y -= 2.83 // 1mm gap

        // ===== EDUCATION & WORK HISTORY =====
        // Section header
        let hdrH: CGFloat = 17.01 // 6mm
        drawFilledBox(ctx: ctx, x: x0, y: y, w: contentW, h: hdrH)
        drawTextCentered("学歴・職歴", at: CGPoint(x: x0 + contentW / 2, y: y - hdrH / 2 - 3),
                         font: PDFFont.japaneseBold(size: 9), in: ctx)
        y -= hdrH

        // Column headers
        let colH = smallH
        drawThreeCols(ctx: ctx, x: x0, y: y, h: colH)
        let colFont = PDFFont.japanese(size: 6)
        drawTextCentered("年", at: CGPoint(x: x0 + yearW / 2, y: y - colH / 2 - 2), font: colFont, in: ctx)
        drawTextCentered("月", at: CGPoint(x: x0 + yearW + monthW / 2, y: y - colH / 2 - 2), font: colFont, in: ctx)
        drawTextCentered("学歴・職歴", at: CGPoint(x: x0 + yearW + monthW + descW / 2, y: y - colH / 2 - 2), font: colFont, in: ctx)
        y -= colH

        // Build history entries
        var entries: [(String, String, String)] = []
        entries.append(("", "", "学　歴"))
        for entry in data.educationHistory {
            let (yr, mo) = splitYearMonth(entry.date)
            entries.append((yr, mo, entry.description))
        }
        entries.append(("", "", ""))
        entries.append(("", "", "職　歴"))
        for entry in data.workHistory {
            let (yr, mo) = splitYearMonth(entry.date)
            entries.append((yr, mo, entry.description))
        }
        entries.append(("", "", "以上"))

        let numRows = max(20, entries.count)
        let rowFont = PDFFont.japanese(size: 6)

        for i in 0..<numRows {
            // Page break if needed (leave room for at least the row)
            newPageIfNeeded(&y, needed: rowH + margin, ctx: ctx, mediaBox: &mediaBox)

            drawThreeCols(ctx: ctx, x: x0, y: y, h: rowH)
            if i < entries.count {
                let (yr, mo, desc) = entries[i]
                let cy = y - rowH / 2 - 2
                drawTextCentered(yr, at: CGPoint(x: x0 + yearW / 2, y: cy), font: rowFont, in: ctx)
                drawTextCentered(mo, at: CGPoint(x: x0 + yearW + monthW / 2, y: cy), font: rowFont, in: ctx)

                let isHeader = desc == "学　歴" || desc == "職　歴"
                let isEnd = desc == "以上"
                if isHeader {
                    drawTextCentered(desc, at: CGPoint(x: x0 + yearW + monthW + descW / 2, y: cy), font: rowFont, in: ctx)
                } else if isEnd {
                    drawTextRight(desc, at: CGPoint(x: x0 + contentW - 8.5, y: cy), font: rowFont, in: ctx)
                } else {
                    drawText(desc, at: CGPoint(x: x0 + yearW + monthW + 5.67, y: cy), font: rowFont, in: ctx)
                }
            }
            y -= rowH
        }

        y -= 2.83

        // ===== LICENSES =====
        let licHdrH: CGFloat = 17.01
        // Ensure licenses + bottom section fit, otherwise new page
        let licensesNeeded = licHdrH + colH + 3 * rowH + 170
        newPageIfNeeded(&y, needed: licensesNeeded, ctx: ctx, mediaBox: &mediaBox)
        drawFilledBox(ctx: ctx, x: x0, y: y, w: contentW, h: licHdrH)
        drawTextCentered("免許・資格", at: CGPoint(x: x0 + contentW / 2, y: y - licHdrH / 2 - 2.5),
                         font: PDFFont.japaneseBold(size: 8), in: ctx)
        y -= licHdrH

        drawThreeCols(ctx: ctx, x: x0, y: y, h: colH)
        drawTextCentered("年", at: CGPoint(x: x0 + yearW / 2, y: y - colH / 2 - 2), font: colFont, in: ctx)
        drawTextCentered("月", at: CGPoint(x: x0 + yearW + monthW / 2, y: y - colH / 2 - 2), font: colFont, in: ctx)
        drawTextCentered("免許・資格", at: CGPoint(x: x0 + yearW + monthW + descW / 2, y: y - colH / 2 - 2), font: colFont, in: ctx)
        y -= colH

        for i in 0..<3 {
            drawThreeCols(ctx: ctx, x: x0, y: y, h: rowH)
            if i < data.licenses.count {
                let (yr, mo) = splitYearMonth(data.licenses[i].date)
                let cy = y - rowH / 2 - 2
                drawTextCentered(yr, at: CGPoint(x: x0 + yearW / 2, y: cy), font: rowFont, in: ctx)
                drawTextCentered(mo, at: CGPoint(x: x0 + yearW + monthW / 2, y: cy), font: rowFont, in: ctx)
                drawText(data.licenses[i].description, at: CGPoint(x: x0 + yearW + monthW + 5.67, y: cy), font: rowFont, in: ctx)
            }
            y -= rowH
        }

        y -= 2.83

        // ===== BOTTOM SECTION =====
        // Motivation
        let motLblH: CGFloat = 14.17 // 5mm
        let motFont = PDFFont.japanese(size: 7)
        let motTextW = contentW - 11.34
        let motTextH: CGFloat
        if let motivation = data.motivation {
            motTextH = measureWrappedText(motivation, maxWidth: motTextW, font: motFont) + 8
        } else {
            motTextH = 28.35 // minimum empty space
        }
        let motH = motLblH + motTextH + 4 // label + text + padding

        newPageIfNeeded(&y, needed: motH, ctx: ctx, mediaBox: &mediaBox)
        drawBox(ctx: ctx, x: x0, y: y, w: contentW, h: motH)
        drawFilledBox(ctx: ctx, x: x0, y: y, w: contentW, h: motLblH)
        drawText("志望の動機、特技、好きな学科、アピールポイントなど",
                 at: CGPoint(x: x0 + 5.67, y: y - motLblH + 4),
                 font: PDFFont.japanese(size: 6), in: ctx)
        if let motivation = data.motivation {
            drawWrappedText(motivation, at: CGPoint(x: x0 + 5.67, y: y - motLblH - 2),
                            maxWidth: motTextW, height: motTextH, font: motFont, in: ctx)
        }
        y -= motH

        // Hobbies
        if let hobbies = data.hobbies {
            let hobH: CGFloat = 28.35 // 10mm
            let hobLblW: CGFloat = 79.37 // 28mm
            drawBox(ctx: ctx, x: x0, y: y, w: contentW, h: hobH)
            drawFilledBox(ctx: ctx, x: x0, y: y, w: hobLblW, h: hobH)
            drawTextCentered("趣味・特技", at: CGPoint(x: x0 + hobLblW / 2, y: y - hobH / 2 - 2.5),
                             font: PDFFont.japanese(size: 7), in: ctx)
            drawText(hobbies, at: CGPoint(x: x0 + hobLblW + 5.67, y: y - hobH / 2 - 2.5),
                     font: PDFFont.japanese(size: 8), in: ctx)
            y -= hobH
        }

        // Bottom info row
        let botH: CGFloat = 34.02 // 12mm
        let botLblH: CGFloat = 14.17 // 5mm
        let colW = contentW / 4

        let items: [(String, String)] = [
            ("通勤時間", data.commuteTime ?? ""),
            ("扶養家族", data.dependentsExclSpouse.map { "\($0)人" } ?? ""),
            ("配偶者", data.spouse == true ? "有" : (data.spouse == false ? "無" : "")),
            ("扶養家族数", data.dependents.map { "\($0)人" } ?? ""),
        ]

        for (idx, (label, value)) in items.enumerated() {
            let bx = x0 + CGFloat(idx) * colW
            drawBox(ctx: ctx, x: bx, y: y, w: colW, h: botH)
            drawFilledBox(ctx: ctx, x: bx, y: y, w: colW, h: botLblH)
            drawTextCentered(label, at: CGPoint(x: bx + colW / 2, y: y - botLblH + 4),
                             font: PDFFont.japanese(size: 6), in: ctx)
            drawTextCentered(value, at: CGPoint(x: bx + colW / 2, y: y - botH / 2 - 5),
                             font: PDFFont.japanese(size: 8), in: ctx)
        }
    }

    // MARK: - Drawing Helpers

    private static func drawBox(ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        ctx.setStrokeColor(CGColor.black)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: x, y: y - h, width: w, height: h))
    }

    private static func drawFilledBox(ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        ctx.setFillColor(gray: 0.96, alpha: 1)
        ctx.fill(CGRect(x: x, y: y - h, width: w, height: h))
        drawBox(ctx: ctx, x: x, y: y, w: w, h: h)
        ctx.setFillColor(CGColor.black)
    }

    private static func drawThreeCols(ctx: CGContext, x: CGFloat, y: CGFloat, h: CGFloat) {
        drawBox(ctx: ctx, x: x, y: y, w: yearW, h: h)
        drawBox(ctx: ctx, x: x + yearW, y: y, w: monthW, h: h)
        drawBox(ctx: ctx, x: x + yearW + monthW, y: y, w: descW, h: h)
    }

    private static func drawLabelRow(ctx: CGContext, x: CGFloat, y: CGFloat,
                                     w: CGFloat, h: CGFloat,
                                     labelW: CGFloat, label: String, value: String,
                                     labelSize: CGFloat, valueSize: CGFloat) {
        drawBox(ctx: ctx, x: x, y: y, w: w, h: h)
        drawFilledBox(ctx: ctx, x: x, y: y, w: labelW, h: h)
        drawTextCentered(label, at: CGPoint(x: x + labelW / 2, y: y - h / 2 - labelSize * 0.2),
                         font: PDFFont.japanese(size: labelSize), in: ctx)
        drawText(value, at: CGPoint(x: x + labelW + 5.67, y: y - h / 2 - valueSize * 0.2),
                 font: PDFFont.japanese(size: valueSize), in: ctx)
    }

    // MARK: - Text Drawing

    private static func drawText(_ text: String, at point: CGPoint, font: NSFont, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private static func drawTextCentered(_ text: String, at point: CGPoint, font: NSFont, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: point.x - width / 2, y: point.y)
        CTLineDraw(line, ctx)
    }

    private static func drawTextRight(_ text: String, at point: CGPoint, font: NSFont, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.textPosition = CGPoint(x: point.x - width, y: point.y)
        CTLineDraw(line, ctx)
    }

    private static func measureWrappedText(_ text: String, maxWidth: CGFloat, font: NSFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude), nil
        )
        return size.height
    }

    private static func drawWrappedText(_ text: String, at point: CGPoint,
                                        maxWidth: CGFloat, height: CGFloat,
                                        font: NSFont, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGMutablePath()
        let frameRect = CGRect(x: point.x, y: point.y - height, width: maxWidth, height: height)
        path.addRect(frameRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)
    }

    private static func splitYearMonth(_ dateStr: String) -> (String, String) {
        guard !dateStr.isEmpty else { return ("", "") }
        if let range = dateStr.range(of: #"(.+?)年(\d+)月?"#, options: .regularExpression) {
            let matched = String(dateStr[range])
            if let yearEnd = matched.range(of: "年") {
                let year = String(matched[matched.startIndex..<yearEnd.lowerBound])
                let rest = String(matched[yearEnd.upperBound...])
                let month = rest.replacingOccurrences(of: "月", with: "")
                return (year, month)
            }
        }
        if let range = dateStr.range(of: #"(.+?)年"#, options: .regularExpression) {
            let year = String(dateStr[dateStr.startIndex..<range.upperBound])
                .replacingOccurrences(of: "年", with: "")
            return (year, "")
        }
        return (dateStr, "")
    }
}

enum PDFError: Error, LocalizedError {
    case cannotCreate

    var errorDescription: String? {
        "Could not create PDF context"
    }
}
