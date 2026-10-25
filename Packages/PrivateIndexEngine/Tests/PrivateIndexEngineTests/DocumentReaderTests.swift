import XCTest
import CoreGraphics
import CoreText
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

    // MARK: - Helper Methods

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
