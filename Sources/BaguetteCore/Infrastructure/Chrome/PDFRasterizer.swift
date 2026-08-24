import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Mockable

/// Inner port for `LiveChromes` — turns PDF bytes into a PNG +
/// pixel-size pair (`ChromeImage`). Mockable so tests don't need to
/// wire CoreGraphics; production uses `CoreGraphicsPDFRasterizer`.
@Mockable
protocol PDFRasterizer: Sendable {
    /// Render the first page of `pdfData` at native scale. Throws if
    /// the bytes aren't a valid PDF or the document has no pages.
    func rasterize(pdfData: Data) throws -> ChromeImage

    /// Stack already-rasterized images onto a canvas of `canvasSize`
    /// and return a single PNG. Layers are drawn in order — the first
    /// entry sits at the back, the last on top. `topLeft` is in canvas
    /// pixel space (origin top-left). `LiveChromes` uses this to bake
    /// chrome buttons behind the device composite into a single
    /// `bezel.png`.
    func compose(canvasSize: Size, layers: [ImageLayer]) throws -> ChromeImage

    /// Compose a DeviceKit 9-slice bezel at an exact screen size.
    /// Output canvas is `innerSize` expanded by `insets` on each side.
    /// Corners keep their own native dimensions; each edge keeps its
    /// own native thickness and stretches only along the gap between
    /// its adjacent corners.
    ///
    /// `innerSize` is the simulator screen's 1× point dimensions
    /// (`mainScreenWidth/Height ÷ mainScreenScale` from the plist).
    /// DeviceKit's `Screen.pdf` ships as a 1×1 marker — meaningless for
    /// sizing — so the caller has to supply the real inner area.
    func compose9Slice(
        pdfs: NineSlicePDFs,
        insets: Insets,
        innerSize: Size
    ) throws -> ChromeImage

    /// Compose a horizontal three-slice decoration. The left and right
    /// caps keep their native widths while the center stretches to fill
    /// the requested size.
    func composeHorizontalSlice(
        pdfs: HorizontalSlicePDFs,
        size: Size
    ) throws -> ChromeImage
}

/// Raw PDF bytes for the eight outer pieces of a 9-slice chrome bundle
/// (4 corners + 4 edges). The center is the simulator's screen area,
/// supplied by the caller as `innerSize` and left transparent in the
/// composed bezel — baguette overlays the live framebuffer on top.
struct NineSlicePDFs: Sendable, Equatable {
    let topLeft: Data
    let top: Data
    let topRight: Data
    let right: Data
    let bottomRight: Data
    let bottom: Data
    let bottomLeft: Data
    let left: Data
}

struct HorizontalSlicePDFs: Sendable, Equatable {
    let left: Data
    let center: Data
    let right: Data
}

/// One entry in a `compose(...)` call — an already-rasterized
/// `ChromeImage` placed at a top-left point in the destination canvas.
/// Carries the source image's intrinsic size (the rasterizer doesn't
/// re-decode it to figure out where to draw) so callers stay
/// declarative.
struct ImageLayer: Sendable, Equatable {
    let image: ChromeImage
    let topLeft: Point
}

enum PDFRasterizerError: Error, Equatable {
    case invalidPDF
    case noPage
    case rasterFailed
    case encodingFailed
    case decodingFailed
}

/// Production rasterizer — uses `CGPDFDocument` to parse, draws the
/// first page into an RGBA `CGContext`, then encodes the result as
/// PNG via `CGImageDestination`.
///
/// Native PDF page size (the `cropBox`, with `mediaBox` fallback) is
/// honoured 1:1 — chrome PDFs are vector and ship at the resolution
/// the layout JSON expects, so the rasterized PNG is the canonical
/// composite that `DeviceChromeAssets.composite.size` reports.
struct CoreGraphicsPDFRasterizer: PDFRasterizer {

    func rasterize(pdfData: Data) throws -> ChromeImage {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let doc = CGPDFDocument(provider) else {
            throw PDFRasterizerError.invalidPDF
        }
        guard let page = doc.page(at: 1) else {
            throw PDFRasterizerError.noPage
        }

        // cropBox is what the PDF asks readers to display; mediaBox is
        // the physical page. Chrome PDFs set them equal, but cropBox
        // is the right primary because it's authoritative if they
        // ever diverge.
        var box = page.getBoxRect(.cropBox)
        if box.isEmpty { box = page.getBoxRect(.mediaBox) }

        let width = Int(box.width.rounded())
        let height = Int(box.height.rounded())
        guard width > 0, height > 0 else { throw PDFRasterizerError.noPage }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFRasterizerError.rasterFailed
        }

        // Translate so the page's lower-left origin lands at (0,0).
        ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        ctx.drawPDFPage(page)

        guard let cgImage = ctx.makeImage() else {
            throw PDFRasterizerError.rasterFailed
        }
        return try ChromeImage(cgImage: cgImage)
    }

    func compose(canvasSize: Size, layers: [ImageLayer]) throws -> ChromeImage {
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard width > 0, height > 0 else { throw PDFRasterizerError.rasterFailed }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFRasterizerError.rasterFailed
        }

        // CGContext's origin is bottom-left; layer positions are
        // top-left, so flip Y at draw time.
        for layer in layers {
            let cgImage = try decode(layer.image)
            let rect = CGRect(
                x: layer.topLeft.x,
                y: Double(height) - layer.topLeft.y - layer.image.size.height,
                width: layer.image.size.width,
                height: layer.image.size.height
            )
            ctx.draw(cgImage, in: rect)
        }

        guard let cgImage = ctx.makeImage() else {
            throw PDFRasterizerError.rasterFailed
        }
        return try ChromeImage(cgImage: cgImage)
    }

    private func decode(_ image: ChromeImage) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(image.data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PDFRasterizerError.decodingFailed
        }
        return cg
    }

    func compose9Slice(
        pdfs: NineSlicePDFs,
        insets: Insets,
        innerSize: Size
    ) throws -> ChromeImage {
        // Each piece is rasterized to a CGImage at its native PDF size
        // first, then drawn into its target rect via `ctx.draw(image,
        // in:)` — the bitmap-stretching path. We can't draw the PDFs
        // with `drawPDFPage` + non-uniform CTM scale because CG ignores
        // the per-axis stretch when the page renders, leaking the source
        // outside the target rect (Apple's edge pieces ship as 1×97 /
        // 97×1 strips meant to be stretched perpendicular to their long
        // axis — exactly the case `drawPDFPage` mishandles).
        let topLeft = try rasterizeCG(pdfs.topLeft)
        let top = try rasterizeCG(pdfs.top)
        let topRight = try rasterizeCG(pdfs.topRight)
        let right = try rasterizeCG(pdfs.right)
        let bottomRight = try rasterizeCG(pdfs.bottomRight)
        let bottom = try rasterizeCG(pdfs.bottom)
        let bottomLeft = try rasterizeCG(pdfs.bottomLeft)
        let left = try rasterizeCG(pdfs.left)

        // Canvas = caller-supplied inner area + insets on each side.
        // Insets define the SCREEN INSET (where the front-end overlays
        // the framebuffer), not the bezel thickness — corner art is
        // drawn at native PDF size and extends past the inset into the
        // inner area, where the screen overlay covers it.
        let canvasW = innerSize.width + insets.left + insets.right
        let canvasH = innerSize.height + insets.top + insets.bottom

        let width = Int(canvasW.rounded())
        let height = Int(canvasH.rounded())
        guard width > 0, height > 0 else { throw PDFRasterizerError.rasterFailed }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFRasterizerError.rasterFailed
        }

        // DeviceKit normally ships symmetric pieces, but the PDFs are
        // individually authoritative. Keeping every corner's native
        // dimensions and every edge's native thickness also handles
        // asymmetric chromes without scaling one piece to TL's size.
        let tlW = CGFloat(topLeft.width), tlH = CGFloat(topLeft.height)
        let trW = CGFloat(topRight.width), trH = CGFloat(topRight.height)
        let brW = CGFloat(bottomRight.width), brH = CGFloat(bottomRight.height)
        let blW = CGFloat(bottomLeft.width), blH = CGFloat(bottomLeft.height)
        let topH = CGFloat(top.height)
        let rightW = CGFloat(right.width)
        let bottomH = CGFloat(bottom.height)
        let leftW = CGFloat(left.width)

        // CG origin is bottom-left; layout below is in CG user space.
        let topLeftRect = CGRect(
            x: 0, y: canvasH - tlH, width: tlW, height: tlH
        )
        let topRightRect = CGRect(
            x: canvasW - trW, y: canvasH - trH, width: trW, height: trH
        )
        let bottomLeftRect = CGRect(
            x: 0, y: 0, width: blW, height: blH
        )
        let bottomRightRect = CGRect(
            x: canvasW - brW, y: 0, width: brW, height: brH
        )

        // Edges stretch only along their seam. Their perpendicular
        // thickness comes from the edge PDF itself, not any corner.
        let topRect = CGRect(
            x: tlW,
            y: canvasH - topH,
            width: max(canvasW - tlW - trW, 0),
            height: topH
        )
        let bottomRect = CGRect(
            x: blW,
            y: 0,
            width: max(canvasW - blW - brW, 0),
            height: bottomH
        )
        let leftRect = CGRect(
            x: 0,
            y: blH,
            width: leftW,
            height: max(canvasH - tlH - blH, 0)
        )
        let rightRect = CGRect(
            x: canvasW - rightW,
            y: brH,
            width: rightW,
            height: max(canvasH - trH - brH, 0)
        )

        for (image, target) in [
            (topLeft,     topLeftRect),
            (topRight,    topRightRect),
            (bottomLeft,  bottomLeftRect),
            (bottomRight, bottomRightRect),
            (top,         topRect),
            (bottom,      bottomRect),
            (left,        leftRect),
            (right,       rightRect),
        ] where target.width > 0 && target.height > 0 {
            ctx.draw(image, in: target)
        }

        guard let cgImage = ctx.makeImage() else {
            throw PDFRasterizerError.rasterFailed
        }
        return try ChromeImage(cgImage: cgImage)
    }

    func composeHorizontalSlice(
        pdfs: HorizontalSlicePDFs,
        size: Size
    ) throws -> ChromeImage {
        let left = try rasterizeCG(pdfs.left)
        let center = try rasterizeCG(pdfs.center)
        let right = try rasterizeCG(pdfs.right)
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else {
            throw PDFRasterizerError.rasterFailed
        }

        let leftWidth = CGFloat(left.width)
        let rightWidth = CGFloat(right.width)
        let centerWidth = max(size.width - leftWidth - rightWidth, 0)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFRasterizerError.rasterFailed
        }

        let targets = [
            (left, CGRect(
                x: 0,
                y: 0,
                width: leftWidth,
                height: size.height
            )),
            (center, CGRect(
                x: leftWidth,
                y: 0,
                width: centerWidth,
                height: size.height
            )),
            (right, CGRect(
                x: size.width - rightWidth,
                y: 0,
                width: rightWidth,
                height: size.height
            )),
        ]
        for (image, target) in targets
        where target.width > 0 && target.height > 0 {
            context.draw(image, in: target)
        }
        guard let image = context.makeImage() else {
            throw PDFRasterizerError.rasterFailed
        }
        return try ChromeImage(cgImage: image)
    }

    /// Render the first page of a PDF to a `CGImage` at native size.
    /// Used by `compose9Slice` so each piece can be drawn into a
    /// stretched target rect via `ctx.draw(image, in:)`, which handles
    /// non-uniform scale correctly (unlike `drawPDFPage`).
    private func rasterizeCG(_ data: Data) throws -> CGImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider) else {
            throw PDFRasterizerError.invalidPDF
        }
        guard let page = doc.page(at: 1) else {
            throw PDFRasterizerError.noPage
        }
        var box = page.getBoxRect(.cropBox)
        if box.isEmpty { box = page.getBoxRect(.mediaBox) }
        let w = Int(box.width.rounded())
        let h = Int(box.height.rounded())
        guard w > 0, h > 0 else { throw PDFRasterizerError.noPage }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw PDFRasterizerError.rasterFailed }
        ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw PDFRasterizerError.rasterFailed }
        return image
    }
}

private extension ChromeImage {
    init(cgImage: CGImage) throws {
        let mutable = NSMutableData()
        let pngType = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(
            mutable, pngType, 1, nil
        ) else {
            throw PDFRasterizerError.encodingFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw PDFRasterizerError.encodingFailed
        }
        self.init(
            data: mutable as Data,
            size: Size(width: Double(cgImage.width), height: Double(cgImage.height))
        )
    }
}
