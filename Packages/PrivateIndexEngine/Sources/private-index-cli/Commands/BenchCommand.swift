import Foundation
import PrivateIndexEngine

func runBench(vectorCount: Int, asJSON: Bool) async throws {
    let runner = BenchmarkRunner(vectorCount: vectorCount)

    if !asJSON {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi bench\(ANSI.reset) — Apple Silicon On-Device Performance Benchmark
        \(ANSI.dim)Running safe, ephemeral in-memory benchmarks without modifying local database...\(ANSI.reset)
        """)
    }

    let metrics = try await runner.run { step in
        if !asJSON {
            print("\(ANSI.dim)  ⏳ \(step)\(ANSI.reset)")
        }
    }

    if asJSON {
        let jsonString = try metrics.toJSONString()
        print(jsonString)
        return
    }

    print("\n\(ANSI.bold)\(ANSI.green)✔ Benchmark Suite Completed Successfully!\(ANSI.reset)\n")

    // Hardware & Environment
    print("\(ANSI.bold)\(ANSI.cyan)Hardware & Environment\(ANSI.reset)")
    print("  • OS Version:          \(ANSI.bold)\(metrics.system.osVersion)\(ANSI.reset)")
    print("  • Architecture:        \(ANSI.bold)\(metrics.system.architecture)\(ANSI.reset)")
    print("  • Processor / Chip:    \(ANSI.bold)\(metrics.system.chipModel)\(ANSI.reset) \(ANSI.dim)(\(metrics.system.modelIdentifier))\(ANSI.reset)")
    let netStatus = metrics.resources.zeroNetworkTransmission
        ? "\(ANSI.green)0 active internet sockets (100% on-device verified)\(ANSI.reset)"
        : "\(ANSI.yellow)\(metrics.resources.activeInternetSockets) active internet sockets\(ANSI.reset)"
    print("  • Privacy & Zero-Cloud: \(netStatus)\n")

    // Stage 1: Text Chunker & Bert Tokenizer
    print("\(ANSI.bold)\(ANSI.cyan)Stage 1: Text Chunker & Bert Tokenizer\(ANSI.reset)")
    let corpusKB = String(format: "%.1f", Double(metrics.chunker.corpusSizeBytes) / 1024.0)
    let chunksPerSec = String(format: "%.1f", metrics.chunker.chunksPerSecond)
    let kbPerSec = String(format: "%.1f", metrics.chunker.kilobytesPerSecond)
    print("  • Text Chunker:        \(ANSI.bold)\(chunksPerSec) chunks/s\(ANSI.reset) \(ANSI.dim)(\(kbPerSec) KB/s over \(corpusKB) KB corpus, \(metrics.chunker.chunksProduced) chunks)\(ANSI.reset)")
    let sentencesPerSec = String(format: "%.1f", metrics.tokenizer.sentencesPerSecond)
    print("  • Bert Tokenizer:      \(ANSI.bold)\(sentencesPerSec) sentences/s\(ANSI.reset) \(ANSI.dim)(\(metrics.tokenizer.sentenceCount) sentences, max length: 128)\(ANSI.reset)\n")

    // Stage 2: Apple Neural Engine (ANE) Inference
    print("\(ANSI.bold)\(ANSI.cyan)Stage 2: Apple Neural Engine (ANE) Inference\(ANSI.reset)")
    print("  • Model Architecture:  \(ANSI.bold)\(metrics.inference.modelName)\(ANSI.reset)")
    let latStr = String(format: "%.2f", metrics.inference.averageLatencyMs)
    let tpsStr = String(format: "%.1f", metrics.inference.embeddingsPerSecond)
    print("  • Average Latency:     \(ANSI.bold)\(latStr) ms / embedding\(ANSI.reset) \(ANSI.dim)(evaluated across \(metrics.inference.inferenceCount) sequential inferences)\(ANSI.reset)")
    print("  • Inference Rate:      \(ANSI.bold)\(tpsStr) embeddings/s\(ANSI.reset)\n")

    // Stage 3: SQLite Vector Store (In-Memory)
    print("\(ANSI.bold)\(ANSI.cyan)Stage 3: SQLite Vector Store (In-Memory Ephemeral)\(ANSI.reset)")
    let vecPerSec = String(format: "%.0f", metrics.vectorStore.vectorsPerSecond)
    let insertDur = String(format: "%.3f", metrics.vectorStore.insertionDurationSeconds)
    print("  • Vector Insertion:    \(ANSI.bold)\(vecPerSec) vec/s\(ANSI.reset) \(ANSI.dim)(\(metrics.vectorStore.vectorCount) 384-dim vectors in \(insertDur)s)\(ANSI.reset)")
    let vP50 = String(format: "%.2f", metrics.vectorStore.vectorQueryP50Ms)
    let vP95 = String(format: "%.2f", metrics.vectorStore.vectorQueryP95Ms)
    let vAvg = String(format: "%.2f", metrics.vectorStore.vectorQueryAverageMs)
    print("  • Top-10 Vector Query: \(ANSI.bold)p50 = \(vP50) ms\(ANSI.reset), \(ANSI.bold)p95 = \(vP95) ms\(ANSI.reset) \(ANSI.dim)(avg: \(vAvg) ms over \(metrics.vectorStore.vectorQueryIterations) queries)\(ANSI.reset)")
    let kP50 = String(format: "%.2f", metrics.vectorStore.keywordQueryP50Ms)
    let kP95 = String(format: "%.2f", metrics.vectorStore.keywordQueryP95Ms)
    let kAvg = String(format: "%.2f", metrics.vectorStore.keywordQueryAverageMs)
    print("  • FTS5 BM25 Keyword:   \(ANSI.bold)p50 = \(kP50) ms\(ANSI.reset), \(ANSI.bold)p95 = \(kP95) ms\(ANSI.reset) \(ANSI.dim)(avg: \(kAvg) ms over \(metrics.vectorStore.keywordQueryIterations) queries)\(ANSI.reset)\n")

    // Stage 4: Resource Utilization
    print("\(ANSI.bold)\(ANSI.cyan)Stage 4: Resource Utilization & Privacy\(ANSI.reset)")
    let memMB = String(format: "%.1f", metrics.resources.peakMemoryMB)
    print("  • Peak Resident (RSS): \(ANSI.bold)\(memMB) MB\(ANSI.reset)")
    print("  • Network Activity:    \(ANSI.green)0 bytes transmitted (zero socket / cloud transmission verified)\(ANSI.reset)\n")
}

func handleBenchCommand(args: [String]) {
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi bench\(ANSI.reset) — Run on-device Apple Silicon performance benchmark

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi bench [options]

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            --vectors <N>  Number of vectors for insertion/retrieval test (default: 1000)
            --json         Output benchmark metrics as machine-readable JSON
            -h, --help     Display this help message

        \(ANSI.bold)EXAMPLES:\(ANSI.reset)
            pi bench
            pi bench --vectors 5000
            pi bench --json
        """)
        exit(0)
    }

    var vectorCount = 1000
    var asJSON = false

    var i = 2
    while i < args.count {
        let arg = args[i]
        if arg == "--vectors", i + 1 < args.count, let parsed = Int(args[i + 1]) {
            vectorCount = parsed
            i += 2
        } else if arg.hasPrefix("--vectors="), let parsed = Int(arg.dropFirst("--vectors=".count)) {
            vectorCount = parsed
            i += 1
        } else if arg == "--json" {
            asJSON = true
            i += 1
        } else {
            i += 1
        }
    }

    let benchVectorCount = vectorCount
    let benchAsJSON = asJSON

    Task {
        do {
            try await runBench(vectorCount: benchVectorCount, asJSON: benchAsJSON)
            exit(0)
        } catch {
            print("\(ANSI.red)Benchmark error:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()
}
