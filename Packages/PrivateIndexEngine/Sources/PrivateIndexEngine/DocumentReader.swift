import Foundation
import CoreGraphics
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(Vision)
import Vision
#endif

// MARK: - DocumentReader

/// Unified text extraction service supporting plain text files, source code, images, and PDF documents.
///
/// For PDF documents, `DocumentReader` implements a two-tier extraction pipeline:
/// 1. **Fast Path (<1ms)**: If a PDF page contains a native digital text layer (`page.string`),
///    it is extracted directly.
/// 2. **OCR Fallback**: If a page is a scanned document or image-only page (missing or fewer
///    than 10 characters), the page is rendered to a CoreGraphics image and processed using
///    Apple's native `Vision` framework (`VNRecognizeTextRequest`) completely on-device.
///
/// For native image files (`.png`, `.jpg`, `.jpeg`, `.heic`, `.webp`, `.tiff`, `.bmp`), `DocumentReader`
/// processes the image directly using Apple's `Vision` framework with automatic EXIF orientation handling,
/// autorelease pool memory management, and reading-order sorting.
public struct DocumentReader: Sendable {

    // MARK: - Supported Image Extensions

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp"
    ]

    // MARK: - Public API

    /// Extracts all text content from the file at `url`.
    ///
    /// - Parameter url: The file URL to read.
    /// - Returns: The extracted plain text string, or `nil` if the file could not be decoded,
    ///   is password-protected, or contains no readable text.
    public static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return extractPDFText(from: url)
        }
        if imageExtensions.contains(ext) {
            return extractImageText(from: url)
        }
        return extractPlainText(from: url)
    }

    // MARK: - Plain Text Extraction

    /// Reads plain text files with encoding fallbacks (.utf8 -> .isoLatin1 -> .windowsCP1252).
    public static func extractPlainText(from url: URL) -> String? {
        // Fast path: UTF-8
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = utf8.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : utf8
        }
        // Fallback: Latin-1 (ISO 8859-1)
        if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            let trimmed = latin1.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : latin1
        }
        // Fallback: Windows CP1252
        if let cp1252 = try? String(contentsOf: url, encoding: .windowsCP1252) {
            let trimmed = cp1252.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : cp1252
        }
        return nil
    }

    // MARK: - PDF Extraction

    #if canImport(PDFKit)
    /// Extracts text from a PDF document, using native text layers where available and
    /// falling back to Vision OCR for scanned/image-only pages.
    public static func extractPDFText(from url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else {
            return nil
        }

        // Encrypted or password-locked PDFs cannot be indexed without credentials
        guard !doc.isLocked else {
            return nil
        }

        var pageTexts: [String] = []

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }

            // 1. Fast Path: Native text layer
            if let nativeStr = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               nativeStr.count >= 10 {
                pageTexts.append(nativeStr)
                continue
            }

            // 2. OCR Fallback: Scanned or image-only page
            #if canImport(Vision)
            if let ocrText = performOCR(on: page) {
                pageTexts.append(ocrText)
                continue
            }
            #endif

            // If OCR failed or was unavailable, check if page.string had any short text at all
            if let fallbackStr = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fallbackStr.isEmpty {
                pageTexts.append(fallbackStr)
            }
        }

        let full = pageTexts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? nil : full
    }

    #if canImport(Vision)
    /// Renders a PDFPage to a CoreGraphics bitmap and executes Apple's on-device `VNRecognizeTextRequest`.
    private static func performOCR(on page: PDFPage) -> String? {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        // Render at 150 DPI for ideal balance of OCR fidelity and processing speed
        let scale: CGFloat = 150.0 / 72.0
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // White background for document contrast
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        guard let cgImage = context.makeImage() else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results, !results.isEmpty else {
            return nil
        }

        let lines = results.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    #endif

    #else
    public static func extractPDFText(from url: URL) -> String? {
        return nil
    }
    #endif

    // MARK: - Image Text Extraction (Vision OCR)

    #if canImport(Vision)
    /// Extracts text from an image file using Apple's on-device `VNRecognizeTextRequest`.
    ///
    /// The image is passed directly by URL to `VNImageRequestHandler` so Vision automatically
    /// reads metadata and honors EXIF orientation tags without inflating full uncompressed bitmaps
    /// into memory. The OCR execution is wrapped in an `@autoreleasepool` to immediately release
    /// Vision allocations.
    ///
    /// - Parameter url: The file URL of the image.
    /// - Returns: The extracted plain text string preserving reading order, or `nil` if no text is found,
    ///   the recognized text is empty, or the file cannot be read as an image.
    public static func extractImageText(from url: URL) -> String? {
        autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if #available(macOS 13.0, iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(url: url, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }

            guard let results = request.results, !results.isEmpty else {
                return nil
            }

            // Reading Order Sorting:
            // VNRecognizedTextObservation normalized coordinates have (0,0) at bottom-left.
            // Sort candidate observations from top to bottom (y descending), then left to right (x ascending),
            // grouping observations with similar vertical positions into lines to preserve reading order.
            let sortedByY = results.sorted { obs1, obs2 in
                obs1.boundingBox.origin.y > obs2.boundingBox.origin.y
            }

            var lineGroups: [[VNRecognizedTextObservation]] = []
            for obs in sortedByY {
                if let lastGroup = lineGroups.last, let firstInGroup = lastGroup.first {
                    let yDelta = abs(obs.boundingBox.origin.y - firstInGroup.boundingBox.origin.y)
                    let threshold = max(0.01, min(obs.boundingBox.height, firstInGroup.boundingBox.height) * 0.5)
                    if yDelta <= threshold {
                        lineGroups[lineGroups.count - 1].append(obs)
                        continue
                    }
                }
                lineGroups.append([obs])
            }

            let sortedObservations = lineGroups.flatMap { group in
                group.sorted { $0.boundingBox.origin.x < $1.boundingBox.origin.x }
            }

            let lines = sortedObservations.compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let trimmed = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
    #else
    public static func extractImageText(from url: URL) -> String? {
        return nil
    }
    #endif
}
