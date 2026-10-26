import Foundation

func printHelp() {
    print("""
    \(ANSI.bold)\(ANSI.cyan)pi\(ANSI.reset) — Private Index: On-Device Semantic Search Engine

    \(ANSI.bold)USAGE:\(ANSI.reset)
        pi <command> [arguments]
        private-index <command> [arguments]

    \(ANSI.bold)COMMANDS:\(ANSI.reset)
        \(ANSI.green)index\(ANSI.reset) <path>            Index documents in the specified directory
        \(ANSI.green)watch\(ANSI.reset) [path...] [options]   Run background watcher daemon (multi-folder & cloud auto-discovery)
        \(ANSI.green)search\(ANSI.reset) <query> [options] Run search for a query (default mode: hybrid)
        \(ANSI.green)bench\(ANSI.reset) [options]         Run on-device Apple Silicon performance benchmark
        \(ANSI.green)stats\(ANSI.reset) (or status)         Show database stats and indexed document counts
        \(ANSI.green)reset\(ANSI.reset)                   Clear database and purge all vector embeddings
        \(ANSI.green)help\(ANSI.reset)                    Display this help message

    \(ANSI.bold)SEARCH OPTIONS:\(ANSI.reset)
        --mode <hybrid|vector|keyword>  Search retrieval mode (default: hybrid)
        --limit <N>                     Maximum number of results to return (default: 10)
        --min-similarity <pct>          Minimum vector similarity percentage (default: 35%, e.g. 40 or 40%)
        --vector-weight <W>             Vector similarity weight for RRF in hybrid mode (default: 0.5)
        --keyword-weight <W>            BM25 keyword weight for RRF in hybrid mode (default: 0.5)
        --json                          Output results as strict JSON array (suppresses banners and formatting)

    \(ANSI.bold)BENCHMARK OPTIONS:\(ANSI.reset)
        --vectors <N>                   Number of vectors for insertion/retrieval test (default: 1,000)
        --json                          Output metrics as machine-readable JSON

    \(ANSI.bold)EXAMPLES:\(ANSI.reset)
        pi index ~/Documents
        pi watch ~/Documents
        pi watch --install-launchagent
        pi watch --uninstall-launchagent
        pi search "zero-cloud privacy architecture"
        pi search "33 bond st" --min-similarity 25%
        pi search "ERR_404_NOT_FOUND" --mode keyword
        pi search "Apple Neural Engine" --mode hybrid --limit 5
        pi search "salary" --json
        pi bench
        pi bench --vectors 5000
        pi bench --json
        pi stats
    """)
}
