import Foundation
import ArgumentParser
import PrivateIndexEngine

extension PrivateIndexCLI {
    struct Search: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "search",
            abstract: "Run search for a query (default mode: hybrid)"
        )

        @Argument(help: "Search query string")
        var query: [String] = []

        @Option(
            name: .customLong("mode"),
            help: "Search retrieval mode (default: hybrid)"
        )
        var mode: String = "hybrid"

        @Option(
            name: .customLong("limit"),
            help: "Maximum number of results to return (default: 10)"
        )
        var limit: Int = 10

        @Option(
            name: [.customLong("min-similarity"), .customLong("threshold")],
            help: "Minimum vector similarity percentage (default: 35%, e.g. 40 or 40%)"
        )
        var minSimilarity: String = "35%"

        @Option(
            name: [.customLong("vector-weight"), .customLong("w-vector")],
            help: "Vector similarity weight for RRF fusion (default: 0.5)"
        )
        var vectorWeight: Float = 0.5

        @Option(
            name: [.customLong("keyword-weight"), .customLong("w-keyword")],
            help: "BM25 keyword weight for RRF fusion (default: 0.5)"
        )
        var keywordWeight: Float = 0.5

        @Flag(
            name: .customLong("json"),
            help: "Output results as strict JSON array (suppresses banners and formatting)"
        )
        var json: Bool = false

        mutating func validate() throws {
            let queryString = query.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !queryString.isEmpty else {
                let msg = "Please specify a search query. e.g. `pi search \"privacy machine learning\"`"
                if json {
                    outputJSONError(msg)
                } else {
                    throw ValidationError(msg)
                }
            }

            guard let _ = SearchMode(rawValue: mode.lowercased()) else {
                let msg = "Invalid mode '\(mode)'. Valid modes: hybrid, vector, keyword."
                if json {
                    outputJSONError(msg)
                } else {
                    throw ValidationError(msg)
                }
            }
        }

        func run() async throws {
            let queryString = query.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let searchMode = SearchMode(rawValue: mode.lowercased()) else {
                let msg = "Invalid mode '\(mode)'. Valid modes: hybrid, vector, keyword."
                if json {
                    outputJSONError(msg)
                } else {
                    throw ValidationError(msg)
                }
            }
            let sim = parseSimilarity(minSimilarity)

            do {
                try await runSearch(
                    query: queryString,
                    limit: limit,
                    mode: searchMode,
                    vectorWeight: vectorWeight,
                    keywordWeight: keywordWeight,
                    minSimilarity: sim,
                    isJSON: json
                )
            } catch {
                if json {
                    outputJSONError(error.localizedDescription)
                } else {
                    print("\(ANSI.red)Search error:\(ANSI.reset) \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            }
        }
    }
}

func parseSimilarity(_ raw: String) -> Float {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasSuffix("%") {
        s = String(s.dropLast())
    }
    guard let val = Float(s) else { return 0.35 }
    if val > 1.0 {
        return max(0.0, min(1.0, val / 100.0))
    }
    return max(0.0, min(1.0, val))
}

func runSearch(
    query: String,
    limit: Int,
    mode: SearchMode = .hybrid,
    vectorWeight: Float = 0.5,
    keywordWeight: Float = 0.5,
    minSimilarity: Float = 0.35,
    isJSON: Bool = false
) async throws {
    let dbURL = defaultDatabaseURL()
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        let msg = "Database not found at '\(dbURL.path)'. Please index documents first using `pi index <directory>`."
        if isJSON {
            outputJSONError(msg)
        } else {
            print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
            exit(1)
        }
    }

    if !isJSON {
        let simPct = Int(round(minSimilarity * 100))
        let simInfo = mode == .keyword ? "" : ", min-similarity: \(simPct)%"
        print("\(ANSI.bold)Query:\(ANSI.reset) \"\(query)\" \(ANSI.dim)(mode: \(mode.rawValue), limit: \(limit)\(simInfo))\(ANSI.reset)\n")
    }

    let (store, coordinator) = try setupEngine()

    let startTime = Date()
    let results = try await coordinator.search(
        query: query,
        limit: limit,
        mode: mode,
        vectorWeight: vectorWeight,
        keywordWeight: keywordWeight,
        minSimilarity: minSimilarity
    )
    let elapsed = Date().timeIntervalSince(startTime) * 1000

    if isJSON {
        if results.isEmpty {
            print("[]")
            return
        }

        var jsonItems: [SearchJSONResult] = []
        for r in results {
            let fileName = URL(fileURLWithPath: r.filePath).lastPathComponent

            var mtime: Int64 = 0
            if let fileRecord = try? store.getFile(byPath: r.filePath) {
                mtime = Int64(fileRecord.mtime.timeIntervalSince1970)
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: r.filePath),
                      let modDate = attrs[.modificationDate] as? Date {
                mtime = Int64(modDate.timeIntervalSince1970)
            }

            let confidence: Int
            if r.matchType == "vector" {
                confidence = max(0, min(100, Int(round((1.0 - r.distance) * 100))))
            } else {
                confidence = max(0, min(100, Int(round(r.score * 100))))
            }

            let roundedScore = Double((Double(r.score) * 10000).rounded() / 10000)
            let roundedDistance = Double((Double(r.distance) * 10000).rounded() / 10000)
            let snippet = r.content.trimmingCharacters(in: .whitespacesAndNewlines)

            jsonItems.append(SearchJSONResult(
                id: r.id,
                filePath: r.filePath,
                fileName: fileName,
                matchType: r.matchType,
                score: roundedScore,
                confidence: confidence,
                distance: roundedDistance,
                snippet: snippet,
                mtime: mtime
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(jsonItems)
        if let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
        return
    }

    if results.isEmpty {
        let indexedCount = (try? store.getAllIndexedFiles().count) ?? 0
        if indexedCount == 0 {
            print("""
            \(ANSI.yellow)No matches found.\(ANSI.reset) You haven't indexed any documents yet.
              • Run \(ANSI.cyan)pi index <directory>\(ANSI.reset) to scan and index a folder.
              • Run \(ANSI.cyan)pi watch [directory] --install-launchagent\(ANSI.reset) to watch 24/7.
            """)
        } else {
            print("""
            \(ANSI.yellow)No matches found for\(ANSI.reset) \"\(ANSI.bold)\(query)\(ANSI.reset)\" \(ANSI.dim)(across \(indexedCount) indexed file\(indexedCount == 1 ? "" : "s"))\(ANSI.reset).
              • Try different keywords or a broader phrasing.
              • Lower the similarity threshold: \(ANSI.cyan)pi search \"\(query)\" --min-similarity 20\(ANSI.reset)
              • Try keyword mode for exact tokens: \(ANSI.cyan)pi search \"\(query)\" --mode keyword\(ANSI.reset)
            """)
        }
        return
    }

    print("\(ANSI.cyan)Found \(results.count) result\(results.count == 1 ? "" : "s") in \(String(format: "%.1f", elapsed))ms:\(ANSI.reset)\n")

    for (idx, r) in results.enumerated() {
        let fileName = URL(fileURLWithPath: r.filePath).lastPathComponent

        let matchPill: String
        switch r.matchType {
        case "hybrid":
            matchPill = "\(ANSI.green)[hybrid]\(ANSI.reset)"
        case "vector":
            matchPill = "\(ANSI.cyan)[vector]\(ANSI.reset)"
        case "keyword":
            matchPill = "\(ANSI.yellow)[keyword]\(ANSI.reset)"
        default:
            matchPill = "[\(r.matchType)]"
        }

        let pct: Int
        if r.matchType == "vector" {
            pct = max(0, min(100, Int(round((1.0 - r.distance) * 100))))
        } else {
            pct = max(0, min(100, Int(round(r.score * 100))))
        }
        let scoreStr = "\(ANSI.bold)\(pct)% match\(ANSI.reset)"

        print("\(ANSI.bold)\(idx + 1). \(fileName)\(ANSI.reset)  \(matchPill) [\(scoreStr)]")
        print("   \(ANSI.dim)\(r.filePath)\(ANSI.reset)")

        // Snippet indented
        let snippet = r.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = snippet.count > 160 ? String(snippet.prefix(160)) + "..." : snippet
        print("   \(preview)\n")
    }
}
