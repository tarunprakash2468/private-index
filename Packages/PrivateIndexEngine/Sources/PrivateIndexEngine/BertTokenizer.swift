import Foundation

// MARK: - TokenizedInput

/// Contains the token IDs and attention mask for transformer model inference.
public struct TokenizedInput: Sendable, Equatable {
    /// Token IDs representing the input text, prefixed with `[CLS]` and suffixed with `[SEP]`.
    public let inputIDs: [Int32]
    /// Attention mask with 1 for real tokens and 0 for padding tokens.
    public let attentionMask: [Int32]

    public init(inputIDs: [Int32], attentionMask: [Int32]) {
        self.inputIDs = inputIDs
        self.attentionMask = attentionMask
    }
}

// MARK: - BertTokenizer

/// A pure-Swift BERT WordPiece tokenizer matching the vocabulary and tokenization scheme
/// of `sentence-transformers/all-MiniLM-L6-v2`.
public final class BertTokenizer: @unchecked Sendable {

    // MARK: - Special Tokens
    public static let padToken = "[PAD]"
    public static let unkToken = "[UNK]"
    public static let clsToken = "[CLS]"
    public static let sepToken = "[SEP]"

    public let padTokenID: Int32
    public let unkTokenID: Int32
    public let clsTokenID: Int32
    public let sepTokenID: Int32

    private let vocab: [String: Int32]
    private let idToToken: [Int32: String]

    // MARK: - Initialization

    /// Initializes the tokenizer using the bundled `vocab.txt` file.
    public convenience init() throws {
        guard let url = ResourceLocator.url(forResource: "vocab", withExtension: "txt") else {
            throw TokenizerError.vocabFileNotFound("vocab.txt not found in resource bundle or search paths")
        }
        try self.init(vocabURL: url)
    }

    /// Initializes the tokenizer using a custom `vocab.txt` file at the specified URL.
    public init(vocabURL: URL) throws {
        let content = try String(contentsOf: vocabURL, encoding: .utf8)
        var map: [String: Int32] = [:]
        var reverseMap: [Int32: String] = [:]

        var id: Int32 = 0
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                map[trimmed] = id
                reverseMap[id] = trimmed
                id += 1
            }
        }

        self.vocab = map
        self.idToToken = reverseMap

        self.padTokenID = map[Self.padToken] ?? 0
        self.unkTokenID = map[Self.unkToken] ?? 100
        self.clsTokenID = map[Self.clsToken] ?? 101
        self.sepTokenID = map[Self.sepToken] ?? 102
    }

    /// Initializes directly with an in-memory vocabulary map (primarily for testing).
    public init(vocab: [String: Int32]) {
        self.vocab = vocab
        var rev: [Int32: String] = [:]
        for (k, v) in vocab {
            rev[v] = k
        }
        self.idToToken = rev

        self.padTokenID = vocab[Self.padToken] ?? 0
        self.unkTokenID = vocab[Self.unkToken] ?? 100
        self.clsTokenID = vocab[Self.clsToken] ?? 101
        self.sepTokenID = vocab[Self.sepToken] ?? 102
    }

    // MARK: - Tokenization

    /// Tokenizes `text` and returns fixed-length `TokenizedInput` padded or truncated to `maxLength`.
    ///
    /// The output array has length `maxLength` with:
    /// - `inputIDs[0]` = `clsTokenID` (101)
    /// - `inputIDs[1...n]` = content token IDs
    /// - `inputIDs[n+1]` = `sepTokenID` (102)
    /// - `inputIDs[n+2...]` = `padTokenID` (0)
    ///
    /// `attentionMask` contains `1` for active tokens (including CLS and SEP) and `0` for padding.
    public func tokenize(_ text: String, maxLength: Int = 128) -> TokenizedInput {
        precondition(maxLength >= 3, "maxLength must be at least 3 for [CLS], token, and [SEP]")

        let words = basicTokenize(text)
        var pieceIDs: [Int32] = []

        // Reserve 2 slots for [CLS] and [SEP]
        let maxContentTokens = maxLength - 2

        for word in words {
            let pieces = wordPieceTokenize(word)
            for piece in pieces {
                if pieceIDs.count < maxContentTokens {
                    pieceIDs.append(piece)
                } else {
                    break
                }
            }
            if pieceIDs.count >= maxContentTokens {
                break
            }
        }

        // Build input_ids and attention_mask
        var inputIDs = [Int32](repeating: padTokenID, count: maxLength)
        var attentionMask = [Int32](repeating: 0, count: maxLength)

        inputIDs[0] = clsTokenID
        attentionMask[0] = 1

        for i in 0..<pieceIDs.count {
            inputIDs[i + 1] = pieceIDs[i]
            attentionMask[i + 1] = 1
        }

        let sepIndex = pieceIDs.count + 1
        inputIDs[sepIndex] = sepTokenID
        attentionMask[sepIndex] = 1

        return TokenizedInput(inputIDs: inputIDs, attentionMask: attentionMask)
    }

    /// Converts token IDs back to a human-readable string (for debugging).
    public func decode(_ tokenIDs: [Int32]) -> String {
        var tokens: [String] = []
        for id in tokenIDs {
            if id == padTokenID { continue }
            if let token = idToToken[id] {
                if token.hasPrefix("##") {
                    if let last = tokens.popLast() {
                        tokens.append(last + token.dropFirst(2))
                    } else {
                        tokens.append(String(token.dropFirst(2)))
                    }
                } else {
                    tokens.append(token)
                }
            }
        }
        return tokens.joined(separator: " ")
    }

    // MARK: - Private Helpers

    /// Basic text cleanup and whitespace/punctuation splitting.
    private func basicTokenize(_ text: String) -> [String] {
        let cleaned = cleanText(text)
        let normalized = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))

        var tokens: [String] = []
        var currentWord = ""

        for char in normalized {
            if isWhitespace(char) {
                if !currentWord.isEmpty {
                    tokens.append(currentWord)
                    currentWord = ""
                }
            } else if isPunctuation(char) {
                if !currentWord.isEmpty {
                    tokens.append(currentWord)
                    currentWord = ""
                }
                tokens.append(String(char))
            } else {
                currentWord.append(char)
            }
        }

        if !currentWord.isEmpty {
            tokens.append(currentWord)
        }

        return tokens
    }

    /// WordPiece subword tokenization for a single word.
    private func wordPieceTokenize(_ word: String) -> [Int32] {
        if word.count > 100 {
            return [unkTokenID]
        }

        var subwords: [Int32] = []
        let chars = Array(word)
        var start = 0

        while start < chars.count {
            var end = chars.count
            var curSubword: String? = nil
            var curID: Int32? = nil

            while start < end {
                var substring = String(chars[start..<end])
                if start > 0 {
                    substring = "##" + substring
                }

                if let id = vocab[substring] {
                    curSubword = substring
                    curID = id
                    break
                }
                end -= 1
            }

            if curSubword == nil, let id = curID {
                subwords.append(id)
            } else if let id = curID {
                subwords.append(id)
                start = end
            } else {
                // Unknown character / subword
                return [unkTokenID]
            }
        }

        return subwords
    }

    private func cleanText(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || isControl(scalar) {
                continue
            }
            if isWhitespace(Character(scalar)) {
                output.append(" ")
            } else {
                output.append(Character(scalar))
            }
        }
        return output
    }

    private func isWhitespace(_ char: Character) -> Bool {
        char.isWhitespace || char == "\t" || char == "\n" || char == "\r"
    }

    private func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 9 || scalar.value == 10 || scalar.value == 13 {
            return false
        }
        let category = scalar.properties.generalCategory
        return category == .control || category == .format
    }

    private func isPunctuation(_ char: Character) -> Bool {
        char.isPunctuation || char.isSymbol
    }

    // MARK: - Errors

    public enum TokenizerError: Error, CustomStringConvertible {
        case vocabFileNotFound(String)

        public var description: String {
            switch self {
            case .vocabFileNotFound(let msg): return "TokenizerError.vocabFileNotFound: \(msg)"
            }
        }
    }
}
