import Foundation
import PrivateIndexEngine

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

func handleSearchCommand(args: [String]) {
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi search\(ANSI.reset) — Run on-device hybrid, vector, or keyword search

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi search <query> [options]

        \(ANSI.bold)ARGUMENTS:\(ANSI.reset)
            <query>                          Search query string

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            --mode <hybrid|vector|keyword>   Search mode (default: hybrid)
            --limit <N>                      Maximum results to return (default: 10)
            --min-similarity <pct>           Minimum vector similarity percentage (default: 35%, e.g. 40 or 40%)
            --vector-weight <W>              Vector similarity weight for RRF fusion (default: 0.5)
            --keyword-weight <W>             BM25 keyword weight for RRF fusion (default: 0.5)
            --json                           Output results as strict JSON array (suppresses banners and formatting)
            -h, --help                       Display this help message

        \(ANSI.bold)EXAMPLES:\(ANSI.reset)
            pi search "33 bond st"
            pi search "33 bond st" --min-similarity 25%
            pi search "meeting notes" --mode hybrid --limit 5
            pi search "ERR_404_NOT_FOUND" --mode keyword
            pi search "salary" --json
        """)
        exit(0)
    }

    var limit = 10
    var mode: SearchMode = .hybrid
    var vectorWeight: Float = 0.5
    var keywordWeight: Float = 0.5
    var minSimilarity: Float = 0.35
    var queryTerms: [String] = []
    var isJSON = false

    var i = 2
    while i < args.count {
        let arg = args[i]
        if arg == "--json" {
            isJSON = true
            i += 1
        } else if arg == "--limit", i + 1 < args.count, let parsedLimit = Int(args[i + 1]) {
            limit = parsedLimit
            i += 2
        } else if arg.hasPrefix("--limit="), let parsedLimit = Int(arg.dropFirst("--limit=".count)) {
            limit = parsedLimit
            i += 1
        } else if arg == "--mode", i + 1 < args.count {
            let modeRaw = args[i + 1].lowercased()
            guard let parsedMode = SearchMode(rawValue: modeRaw) else {
                let msg = "Invalid mode '\(args[i + 1])'. Valid modes: hybrid, vector, keyword."
                if isJSON || args.contains("--json") {
                    outputJSONError(msg)
                } else {
                    print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
                    exit(1)
                }
            }
            mode = parsedMode
            i += 2
        } else if arg.hasPrefix("--mode=") {
            let modeRaw = String(arg.dropFirst("--mode=".count)).lowercased()
            guard let parsedMode = SearchMode(rawValue: modeRaw) else {
                let msg = "Invalid mode '\(modeRaw)'. Valid modes: hybrid, vector, keyword."
                if isJSON || args.contains("--json") {
                    outputJSONError(msg)
                } else {
                    print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
                    exit(1)
                }
            }
            mode = parsedMode
            i += 1
        } else if (arg == "--min-similarity" || arg == "--threshold"), i + 1 < args.count {
            minSimilarity = parseSimilarity(args[i + 1])
            i += 2
        } else if arg.hasPrefix("--min-similarity=") {
            let val = String(arg.dropFirst("--min-similarity=".count))
            minSimilarity = parseSimilarity(val)
            i += 1
        } else if arg.hasPrefix("--threshold=") {
            let val = String(arg.dropFirst("--threshold=".count))
            minSimilarity = parseSimilarity(val)
            i += 1
        } else if (arg == "--vector-weight" || arg == "--w-vector"), i + 1 < args.count, let weight = Float(args[i + 1]) {
            vectorWeight = weight
            i += 2
        } else if arg.hasPrefix("--vector-weight="), let weight = Float(arg.dropFirst("--vector-weight=".count)) {
            vectorWeight = weight
            i += 1
        } else if (arg == "--keyword-weight" || arg == "--w-keyword"), i + 1 < args.count, let weight = Float(args[i + 1]) {
            keywordWeight = weight
            i += 2
        } else if arg.hasPrefix("--keyword-weight="), let weight = Float(arg.dropFirst("--keyword-weight=".count)) {
            keywordWeight = weight
            i += 1
        } else {
            queryTerms.append(args[i])
            i += 1
        }
    }

    let query = queryTerms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
        let msg = "Please specify a search query. e.g. `pi search \"privacy machine learning\"`"
        if isJSON {
            outputJSONError(msg)
        } else {
            print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
            exit(1)
        }
    }

    let searchLimit = limit
    let searchMode = mode
    let searchVectorWeight = vectorWeight
    let searchKeywordWeight = keywordWeight
    let searchMinSimilarity = minSimilarity
    let searchIsJSON = isJSON

    Task {
        do {
            try await runSearch(
                query: query,
                limit: searchLimit,
                mode: searchMode,
                vectorWeight: searchVectorWeight,
                keywordWeight: searchKeywordWeight,
                minSimilarity: searchMinSimilarity,
                isJSON: searchIsJSON
            )
            exit(0)
        } catch {
            if searchIsJSON {
                outputJSONError(error.localizedDescription)
            } else {
                print("\(ANSI.red)Search error:\(ANSI.reset) \(error.localizedDescription)")
                exit(1)
            }
        }
    }
    RunLoop.main.run()
}
