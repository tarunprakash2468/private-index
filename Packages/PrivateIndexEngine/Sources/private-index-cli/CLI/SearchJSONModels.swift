import Foundation

struct SearchJSONResult: Encodable {
    let id: Int64
    let filePath: String
    let fileName: String
    let matchType: String
    let score: Double
    let confidence: Int
    let distance: Double
    let snippet: String
    let mtime: Int64
}

func outputJSONError(_ message: String, code: Int32 = 1) -> Never {
    let dict = ["error": message]
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
        FileHandle.standardError.write(Data((str + "\n").utf8))
    } else {
        FileHandle.standardError.write(Data("{\"error\": \"\(message)\"}\n".utf8))
    }
    exit(code)
}
