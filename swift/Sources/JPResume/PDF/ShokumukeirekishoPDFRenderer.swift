import AppKit
import CoreGraphics
import CoreText
import Foundation

enum ShokumukeirekishoPDFRenderer {
    private static let pageW: CGFloat = 595.27
    private static let pageH: CGFloat = 841.89
    private static let margin: CGFloat = 28.35

    static func render(data: ShokumukeirekishoData, to url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PDFError.cannotCreate
        }

        let contentW = pageW - 2 * margin
        var y = pageH - margin

        func newPageIfNeeded(needed: CGFloat) {
            if y - needed < margin {
                ctx.endPage()
                ctx.beginPage(mediaBox: &mediaBox)
                y = pageH - margin
            }
        }

        ctx.beginPage(mediaBox: &mediaBox)

        // Title
        drawText("職務経歴書", at: CGPoint(x: margin, y: y - 14),
                 font: PDFFont.japaneseBold(size: 16), in: ctx)
        y -= 22

        // Date and name
        let infoFont = PDFFont.japanese(size: 8)
        drawText("作成日: \(data.creationDate)", at: CGPoint(x: margin, y: y - 8), font: infoFont, in: ctx)
        y -= 14
        drawText("氏名: \(data.name)", at: CGPoint(x: margin, y: y - 8), font: infoFont, in: ctx)
        y -= 18

        // HR
        drawHR(ctx: ctx, y: y, x: margin, w: contentW)
        y -= 8

        // Career Summary
        drawText("職務要約", at: CGPoint(x: margin, y: y - 12),
                 font: PDFFont.japaneseBold(size: 12), in: ctx)
        y -= 20

        y = drawParagraph(data.careerSummary, at: CGPoint(x: margin, y: y),
                          maxWidth: contentW, font: PDFFont.japanese(size: 9), lineHeight: 14, in: ctx)
        y -= 14

        drawHR(ctx: ctx, y: y, x: margin, w: contentW)
        y -= 8

        // Work Details
        drawText("職務経歴", at: CGPoint(x: margin, y: y - 12),
                 font: PDFFont.japaneseBold(size: 12), in: ctx)
        y -= 24

        for company in data.workDetails {
            newPageIfNeeded(needed: 80)

            // Company header
            drawText("\(company.companyName)（\(company.period)）",
                     at: CGPoint(x: margin, y: y - 10),
                     font: PDFFont.japaneseBold(size: 10), in: ctx)
            y -= 16

            let detailFont = PDFFont.japanese(size: 8)
            if let industry = company.industry {
                drawText("事業内容: \(industry)", at: CGPoint(x: margin + 8, y: y - 8), font: detailFont, in: ctx)
                y -= 12
            }
            if let role = company.role {
                var roleText = role
                if let dept = company.department { roleText += "（\(dept)）" }
                drawText(roleText, at: CGPoint(x: margin + 8, y: y - 8),
                         font: PDFFont.japaneseBold(size: 9), in: ctx)
                y -= 14
            }

            if !company.responsibilities.isEmpty {
                drawText("業務内容:", at: CGPoint(x: margin + 8, y: y - 8),
                         font: PDFFont.japaneseBold(size: 8), in: ctx)
                y -= 14
                for item in company.responsibilities {
                    newPageIfNeeded(needed: 14)
                    drawText("・\(item)", at: CGPoint(x: margin + 14, y: y - 8), font: detailFont, in: ctx)
                    y -= 12
                }
            }

            if !company.achievements.isEmpty {
                y -= 4
                drawText("主な実績:", at: CGPoint(x: margin + 8, y: y - 8),
                         font: PDFFont.japaneseBold(size: 8), in: ctx)
                y -= 14
                for item in company.achievements {
                    newPageIfNeeded(needed: 14)
                    drawText("・\(item)", at: CGPoint(x: margin + 14, y: y - 8), font: detailFont, in: ctx)
                    y -= 12
                }
            }

            y -= 8
            drawHR(ctx: ctx, y: y, x: margin, w: contentW)
            y -= 8
        }

        // Technical Skills
        newPageIfNeeded(needed: 40)
        drawText("活かせる経験・知識・技術", at: CGPoint(x: margin, y: y - 12),
                 font: PDFFont.japaneseBold(size: 12), in: ctx)
        y -= 24

        let skillFont = PDFFont.japanese(size: 8)
        let skillBoldFont = PDFFont.japaneseBold(size: 8)
        for (category, skills) in data.technicalSkills {
            newPageIfNeeded(needed: 14)
            drawText("\(category): ", at: CGPoint(x: margin + 8, y: y - 8), font: skillBoldFont, in: ctx)
            // Measure category label width and draw skills after it
            let labelWidth = measureText("\(category): ", font: skillBoldFont)
            drawText(skills.joined(separator: ", "),
                     at: CGPoint(x: margin + 8 + labelWidth, y: y - 8), font: skillFont, in: ctx)
            y -= 14
        }

        y -= 8
        drawHR(ctx: ctx, y: y, x: margin, w: contentW)
        y -= 8

        // Self PR
        if let pr = data.selfPr {
            newPageIfNeeded(needed: 40)
            drawText("自己PR", at: CGPoint(x: margin, y: y - 12),
                     font: PDFFont.japaneseBold(size: 12), in: ctx)
            y -= 20

            _ = drawParagraph(pr, at: CGPoint(x: margin, y: y),
                              maxWidth: contentW, font: PDFFont.japanese(size: 9),
                              lineHeight: 14, in: ctx)
        }

        ctx.endPage()
        ctx.closePDF()
    }

    // MARK: - Helpers

    private static func drawText(_ text: String, at point: CGPoint, font: NSFont, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private static func measureText(_ text: String, font: NSFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private static func drawHR(ctx: CGContext, y: CGFloat, x: CGFloat, w: CGFloat) {
        ctx.setStrokeColor(gray: 0.8, alpha: 1)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + w, y: y))
        ctx.strokePath()
        ctx.setStrokeColor(CGColor.black)
    }

    @discardableResult
    private static func drawParagraph(_ text: String, at point: CGPoint,
                                      maxWidth: CGFloat, font: NSFont,
                                      lineHeight: CGFloat, in ctx: CGContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)

        // Measure needed height
        let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0),
            nil, CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude), nil
        )

        let path = CGMutablePath()
        let frameRect = CGRect(x: point.x, y: point.y - suggestedSize.height,
                               width: maxWidth, height: suggestedSize.height)
        path.addRect(frameRect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, ctx)

        return point.y - suggestedSize.height
    }
}
