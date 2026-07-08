import Foundation
import CryptoKit
import os

actor VoiceEmbeddingRegistry {
    static let shared = VoiceEmbeddingRegistry()

    struct EmbeddingRecord: Codable, Sendable {
        let canonicalName: String
        let embedding: [Float]
        let sha256: String
        let sampleRate: Double
        let source: Source
        let updatedAt: Date

        enum Source: String, Codable, Sendable {
            case userRecorded
            case preset
            case cloned
        }
    }

    private var embeddings: [String: EmbeddingRecord] = [:]
    private var aliases: [String: String] = [:]

    func register(
        canonicalName: String,
        embedding: [Float],
        sampleRate: Double = 16000,
        source: EmbeddingRecord.Source = .userRecorded
    ) -> String {
        let key = Self.embeddingHash(embedding)
        let record = EmbeddingRecord(
            canonicalName: canonicalName,
            embedding: embedding,
            sha256: key,
            sampleRate: sampleRate,
            source: source,
            updatedAt: Date()
        )
        embeddings[canonicalName] = record
        return key
    }

    func registerAliases(_ aliases: [String], for canonicalName: String) {
        for alias in aliases {
            self.aliases[alias] = canonicalName
        }
    }

    func resolve(_ name: String) -> EmbeddingRecord? {
        let canonical = aliases[name] ?? name
        return embeddings[canonical]
    }

    func embedding(for name: String) -> [Float]? {
        resolve(name)?.embedding
    }

    func cacheKey(for name: String, text: String, emotionTag: String) -> String {
        guard let record = resolve(name) else {
            return "default_\(text.hashValue)_\(emotionTag)"
        }
        return "\(record.sha256.prefix(16))_\(emotionTag)_\(text.hashValue)"
    }

    func listForBook(_ bookID: UUID) -> [EmbeddingRecord] {
        // Filter by bookID if needed - for now return all
        Array(embeddings.values)
    }

    nonisolated static func embeddingHash(_ embedding: [Float]) -> String {
        let data = Data(embedding.map { $0.bitPattern }.flatMap { withUnsafeBytes(of: $0) { Array($0) } })
        let digest = SHA256.hash(data: data)
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }
}