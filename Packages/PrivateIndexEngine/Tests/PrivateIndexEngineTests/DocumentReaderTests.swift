import XCTest
import CoreGraphics
import CoreText
import ImageIO
#if canImport(PDFKit)
import PDFKit
#endif
@testable import PrivateIndexEngine

final class DocumentReaderTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentReaderTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Plain Text Tests

    func testPlainTextExtractionUTF8() throws {
        let fileURL = tempDir.appendingPathComponent("sample.txt")
        let content = "Hello, world! This is a UTF-8 test document with symbols: ⚡️ 🧠 🚀."
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let extracted = DocumentReader.extractText(from: fileURL)
        XCTAssertEqual(extracted, content)
    }

    func testPlainTextExtractionLatin1Fallback() throws {
        let fileURL = tempDir.appendingPathComponent("latin1.txt")
        let rawBytes: [UInt8] = [0x54, 0x65, 0x73, 0x74, 0x20, 0xE9, 0x20, 0xE0] // "Test é à" in Latin-1
        let data = Data(rawBytes)
        try data.write(to: fileURL)

        let extracted = DocumentReader.extractText(from: fileURL)
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted?.contains("Test") == true)
    }

    func testEmptyFileReturnsNil() throws {
        let emptyURL = tempDir.appendingPathComponent("empty.txt")
        try "".write(to: emptyURL, atomically: true, encoding: .utf8)

        let extracted = DocumentReader.extractText(from: emptyURL)
        XCTAssertNil(extracted)
    }

    func testWhitespaceOnlyReturnsNil() throws {
        let fileURL = tempDir.appendingPathComponent("whitespace.txt")
        try "   \n\t  \r\n   ".write(to: fileURL, atomically: true, encoding: .utf8)

        let extracted = DocumentReader.extractText(from: fileURL)
        XCTAssertNil(extracted)
    }

    func testNonExistentFileReturnsNil() {
        let nonExistent = tempDir.appendingPathComponent("ghost.txt")
        let extracted = DocumentReader.extractText(from: nonExistent)
        XCTAssertNil(extracted)
    }

    // MARK: - Digital PDF Tests

    func testDigitalPDFExtraction() throws {
        let pdfURL = tempDir.appendingPathComponent("digital_document.pdf")
        let expectedText = "Private Index is an on-device semantic search engine for Apple platforms."
        createDigitalPDF(at: pdfURL, text: expectedText)

        let extracted = DocumentReader.extractText(from: pdfURL)
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted?.contains("Private Index") == true)
        XCTAssertTrue(extracted?.contains("semantic search engine") == true)
    }

    // MARK: - Scanned / Image-Only PDF Tests (Vision OCR)

    func testScannedImageOnlyPDFExtractionViaOCR() throws {
        let pdfURL = tempDir.appendingPathComponent("scanned_receipt.pdf")
        let invoiceText = "INVOICE #9824 TOTAL DUE: $1,250.00"
        createScannedPDF(at: pdfURL, text: invoiceText)

        // Native string on the raster page should be nil or empty
        #if canImport(PDFKit)
        let doc = PDFDocument(url: pdfURL)
        let nativeString = doc?.page(at: 0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(nativeString == nil || nativeString?.isEmpty == true)
        #endif

        // DocumentReader should trigger Vision OCR and successfully recognize the text
        let extracted = DocumentReader.extractText(from: pdfURL)
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted?.contains("INVOICE") == true, "Extracted text was: \(extracted ?? "nil")")
        XCTAssertTrue(extracted?.contains("9824") == true, "Extracted text was: \(extracted ?? "nil")")
    }

    // MARK: - Native Image OCR Tests (Vision OCR)

    func testNonImageOrCorruptImageReturnsNilWithoutCrashing() throws {
        // Corrupt file with .png extension
        let corruptPNG = tempDir.appendingPathComponent("corrupt.png")
        try "this is not a valid png image data".write(to: corruptPNG, atomically: true, encoding: .utf8)
        XCTAssertNil(DocumentReader.extractText(from: corruptPNG))
        XCTAssertNil(DocumentReader.extractImageText(from: corruptPNG))

        // 0-byte file with .png extension
        let emptyPNG = tempDir.appendingPathComponent("empty.png")
        FileManager.default.createFile(atPath: emptyPNG.path, contents: Data())
        XCTAssertNil(DocumentReader.extractText(from: emptyPNG))
        XCTAssertNil(DocumentReader.extractImageText(from: emptyPNG))

        // Non-existent image file
        let ghostPNG = tempDir.appendingPathComponent("ghost.png")
        XCTAssertNil(DocumentReader.extractText(from: ghostPNG))
        XCTAssertNil(DocumentReader.extractImageText(from: ghostPNG))

        // Directory ending in .png
        let dirPNG = tempDir.appendingPathComponent("folder.png")
        try FileManager.default.createDirectory(at: dirPNG, withIntermediateDirectories: true)
        XCTAssertNil(DocumentReader.extractText(from: dirPNG))
        XCTAssertNil(DocumentReader.extractImageText(from: dirPNG))

        // Corrupt files with other image extensions
        for ext in ["jpg", "jpeg", "heic", "webp", "tiff", "bmp"] {
            let corruptFile = tempDir.appendingPathComponent("corrupt.\(ext)")
            try "corrupt binary bytes".write(to: corruptFile, atomically: true, encoding: .utf8)
            XCTAssertNil(DocumentReader.extractText(from: corruptFile))
        }
    }

    func testImageExtractionWithRenderedText() throws {
        let pngURL = tempDir.appendingPathComponent("receipt.png")
        let text = "RECEIPT #9482 AMOUNT: $89.99"
        createImage(at: pngURL, text: text)

        let extracted = DocumentReader.extractText(from: pngURL)
        XCTAssertNotNil(extracted)
        XCTAssertTrue(extracted?.contains("RECEIPT") == true, "Extracted was: \(extracted ?? "nil")")
        XCTAssertTrue(extracted?.contains("9482") == true, "Extracted was: \(extracted ?? "nil")")
        XCTAssertTrue(extracted?.contains("89.99") == true, "Extracted was: \(extracted ?? "nil")")
    }

    func testImageExtractionSupportedFormats() throws {
        // Test .png
        let pngURL = tempDir.appendingPathComponent("sample.png")
        createImage(at: pngURL, text: "PNG TEST DOCUMENT", format: "public.png")
        let pngExtracted = DocumentReader.extractText(from: pngURL)
        XCTAssertTrue(pngExtracted?.contains("PNG") == true)
        XCTAssertTrue(pngExtracted?.contains("TEST") == true)

        // Test .jpg / .jpeg
        let jpgURL = tempDir.appendingPathComponent("sample.jpg")
        createImage(at: jpgURL, text: "JPEG RECEIPT AUDIT", format: "public.jpeg")
        let jpgExtracted = DocumentReader.extractText(from: jpgURL)
        XCTAssertTrue(jpgExtracted?.contains("JPEG") == true)
        XCTAssertTrue(jpgExtracted?.contains("RECEIPT") == true)

        // Test .heic
        let heicURL = tempDir.appendingPathComponent("sample.heic")
        createImage(at: heicURL, text: "HEIC PHOTO TEXT", format: "public.heic")
        let heicExtracted = DocumentReader.extractText(from: heicURL)
        XCTAssertTrue(heicExtracted?.contains("HEIC") == true)
        XCTAssertTrue(heicExtracted?.contains("PHOTO") == true)

        // Test .tiff
        let tiffURL = tempDir.appendingPathComponent("sample.tiff")
        createImage(at: tiffURL, text: "TIFF HIGH RES SCAN", format: "public.tiff")
        let tiffExtracted = DocumentReader.extractText(from: tiffURL)
        XCTAssertTrue(tiffExtracted?.contains("TIFF") == true)

        // Test .bmp
        let bmpURL = tempDir.appendingPathComponent("sample.bmp")
        createImage(at: bmpURL, text: "BITMAP LEGACY GRAPHIC", format: "com.microsoft.bmp")
        let bmpExtracted = DocumentReader.extractText(from: bmpURL)
        XCTAssertTrue(bmpExtracted?.contains("BITMAP") == true)

        // Test .webp (via base64 fixture containing "WEBP TEST SUCCESS")
        let webpURL = tempDir.appendingPathComponent("sample.webp")
        try createSampleWebP(at: webpURL)
        let webpExtracted = DocumentReader.extractText(from: webpURL)
        XCTAssertNotNil(webpExtracted)
        XCTAssertTrue(webpExtracted?.contains("WEBP") == true, "Extracted was: \(webpExtracted ?? "nil")")
        XCTAssertTrue(webpExtracted?.contains("SUCCESS") == true, "Extracted was: \(webpExtracted ?? "nil")")
    }

    func testImageExtensionCaseInsensitivity() throws {
        let uppercasePNG = tempDir.appendingPathComponent("photo.PNG")
        createImage(at: uppercasePNG, text: "UPPERCASE PNG DATA", format: "public.png")
        let pngResult = DocumentReader.extractText(from: uppercasePNG)
        XCTAssertTrue(pngResult?.contains("UPPERCASE") == true)

        let uppercaseJPG = tempDir.appendingPathComponent("photo.JPG")
        createImage(at: uppercaseJPG, text: "UPPERCASE JPG DATA", format: "public.jpeg")
        let jpgResult = DocumentReader.extractText(from: uppercaseJPG)
        XCTAssertTrue(jpgResult?.contains("UPPERCASE") == true)

        let uppercaseHEIC = tempDir.appendingPathComponent("photo.HEIC")
        createImage(at: uppercaseHEIC, text: "UPPERCASE HEIC DATA", format: "public.heic")
        let heicResult = DocumentReader.extractText(from: uppercaseHEIC)
        XCTAssertTrue(heicResult?.contains("UPPERCASE") == true)

        let mixedWebP = tempDir.appendingPathComponent("photo.WeBp")
        try createSampleWebP(at: mixedWebP)
        let webpResult = DocumentReader.extractText(from: mixedWebP)
        XCTAssertTrue(webpResult?.contains("WEBP") == true)
    }

    func testImageReadingOrderSorting() throws {
        let multiLineURL = tempDir.appendingPathComponent("multiline.png")
        // In CoreGraphics context (height = 400), y = 280 is top, y = 80 is bottom
        createMultiLineImage(at: multiLineURL, lines: [
            (text: "FIRST HEADER LINE", y: 280),
            (text: "SECOND FOOTER LINE", y: 80)
        ])

        let extracted = DocumentReader.extractText(from: multiLineURL)
        XCTAssertNotNil(extracted)
        guard let text = extracted else { return }

        guard let firstRange = text.range(of: "FIRST HEADER LINE"),
              let secondRange = text.range(of: "SECOND FOOTER LINE") else {
            XCTFail("Missing expected lines in extracted text: \(text)")
            return
        }

        XCTAssertTrue(
            firstRange.upperBound <= secondRange.lowerBound,
            "Expected top-most line to appear before bottom-most line. Extracted text was:\n\(text)"
        )
    }

    func testBlankImageReturnsNil() throws {
        let blankURL = tempDir.appendingPathComponent("blank.png")
        createImage(at: blankURL, text: "", format: "public.png")

        let extracted = DocumentReader.extractText(from: blankURL)
        XCTAssertNil(extracted)
    }

    // MARK: - End-to-End IndexCoordinator Integration

    func testIndexCoordinatorWithMixedDocuments() async throws {
        let vectorStore = try VectorStore(at: nil)
        try vectorStore.createSchema()

        let coordinator = IndexCoordinator(
            vectorStore: vectorStore,
            fileCrawler: FileCrawler(),
            textChunker: TextChunker(windowSize: 200, overlap: 50),
            embeddingModel: MockEmbeddingModel()
        )

        // Add 1 Markdown file, 1 digital PDF, and 1 scanned PDF
        let mdURL = tempDir.appendingPathComponent("notes.md")
        try "Architectural notes about Apple Silicon and Neural Engine acceleration.".write(
            to: mdURL,
            atomically: true,
            encoding: .utf8
        )

        let digitalPdfURL = tempDir.appendingPathComponent("specs.pdf")
        createDigitalPDF(at: digitalPdfURL, text: "Specification document for high dimensional vector indexing.")

        let scannedPdfURL = tempDir.appendingPathComponent("invoice.pdf")
        createScannedPDF(at: scannedPdfURL, text: "INVOICE #7741 PAYMENT PROCESSED")

        let report = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(report.filesScanned, 3)
        XCTAssertEqual(report.filesIndexed, 3)
        XCTAssertEqual(report.filesSkipped, 0)
        XCTAssertGreaterThan(report.chunksIndexed, 2)

        // Query matching the scanned PDF (using exact text for deterministic MockEmbeddingModel hash)
        let results = try await coordinator.search(query: "INVOICE #7741 PAYMENT PROCESSED", limit: 5)
        XCTAssertFalse(results.isEmpty)
        let topResult = results[0]
        XCTAssertTrue(topResult.filePath.hasSuffix("invoice.pdf"))
    }

    func testIndexCoordinatorWithImageDocument() async throws {
        let vectorStore = try VectorStore(at: nil)
        try vectorStore.createSchema()

        let coordinator = IndexCoordinator(
            vectorStore: vectorStore,
            fileCrawler: FileCrawler(),
            textChunker: TextChunker(windowSize: 200, overlap: 50),
            embeddingModel: MockEmbeddingModel()
        )

        let imageURL = tempDir.appendingPathComponent("screenshot.png")
        createImage(at: imageURL, text: "PROMPT ENGINEERING AND KNOWLEDGE RETRIEVAL")

        let report = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(report.filesScanned, 1)
        XCTAssertEqual(report.filesIndexed, 1)
        XCTAssertEqual(report.filesSkipped, 0)
        XCTAssertGreaterThan(report.chunksIndexed, 0)

        let results = try await coordinator.search(query: "PROMPT ENGINEERING AND KNOWLEDGE RETRIEVAL", limit: 5)
        XCTAssertFalse(results.isEmpty)
        let topResult = results[0]
        XCTAssertTrue(topResult.filePath.hasSuffix("screenshot.png"))
    }

    // MARK: - Helper Methods

    private func createImage(
        at url: URL,
        text: String,
        format: String = "public.png",
        width: Int = 800,
        height: Int = 200
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        bitmapCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmapCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if !text.isEmpty {
            let attrStr = NSAttributedString(
                string: text,
                attributes: [
                    .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 32, nil),
                    .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
            let textPath = CGPath(rect: CGRect(x: 30, y: 30, width: CGFloat(width - 60), height: CGFloat(height - 60)), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrStr.length), textPath, nil)
            CTFrameDraw(frame, bitmapCtx)
        }

        guard let cgImage = bitmapCtx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, format as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    private func createMultiLineImage(at url: URL, lines: [(text: String, y: CGFloat)]) {
        let width = 800
        let height = 400
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        bitmapCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmapCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for item in lines {
            let attrStr = NSAttributedString(
                string: item.text,
                attributes: [
                    .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil),
                    .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                ]
            )
            let framesetter = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
            let textPath = CGPath(rect: CGRect(x: 40, y: item.y, width: CGFloat(width - 80), height: 60), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrStr.length), textPath, nil)
            CTFrameDraw(frame, bitmapCtx)
        }

        guard let cgImage = bitmapCtx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }

    private func createSampleWebP(at url: URL) throws {
        // Base64 of a valid WebP image containing the text "WEBP TEST SUCCESS"
        let webpBase64 = "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"
        guard let data = Data(base64Encoded: webpBase64) else {
            throw XCTSkip("Failed to decode sample webp base64")
        }
        try data.write(to: url)
    }

    private func createDigitalPDF(at url: URL, text: String) {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return
        }
        context.beginPDFPage(nil)
        let attrStr = NSAttributedString(
            string: text,
            attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 18, nil)
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 50, y: 500, width: 500, height: 200), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrStr.length), path, nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
        context.closePDF()
    }

    private func createScannedPDF(at url: URL, text: String) {
        // 1. Render text into a pure raster bitmap (no vector text retained)
        let imgWidth = 800
        let imgHeight = 200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapCtx = CGContext(
            data: nil,
            width: imgWidth,
            height: imgHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        bitmapCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmapCtx.fill(CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))

        let attrStr = NSAttributedString(
            string: text,
            attributes: [
                .font: CTFontCreateWithName("Helvetica-Bold" as CFString, 32, nil),
                .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr as CFAttributedString)
        let textPath = CGPath(rect: CGRect(x: 30, y: 50, width: 740, height: 100), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrStr.length), textPath, nil)
        CTFrameDraw(frame, bitmapCtx)

        guard let cgImage = bitmapCtx.makeImage() else { return }

        // 2. Insert image into a PDF without any vector text elements
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdfCtx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return
        }
        pdfCtx.beginPDFPage(nil)
        pdfCtx.draw(cgImage, in: CGRect(x: 50, y: 500, width: 512, height: 128))
        pdfCtx.endPDFPage()
        pdfCtx.closePDF()
    }
}
