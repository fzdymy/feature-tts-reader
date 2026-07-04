import CoreML
import Foundation

final class NEREngine {
    private let model: MLModel
    private let vocab: [String: Int]
    private let maxLen = 512
    private let overlap = 128

    private let personLabels: Set<Int> = [14, 32, 50, 68]

    private let outputName: String

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let modelURL: URL
        if let url = Bundle.main.url(forResource: "ckip_ner_q8", withExtension: "mlpackage") {
            modelURL = url
        } else if let url = Bundle.module.url(forResource: "ckip_ner_q8", withExtension: "mlpackage") {
            modelURL = url
        } else {
            // Development fallback: relative to package source
            let devPath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/ckip_ner_q8.mlpackage")
            if FileManager.default.fileExists(atPath: devPath.path) {
                modelURL = devPath
            } else {
                throw NRError.modelNotFound
            }
        }
        model = try MLModel(contentsOf: modelURL, configuration: config)

        let vocabURL: URL
        if let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
            vocabURL = url
        } else if let url = Bundle.module.url(forResource: "vocab", withExtension: "txt") {
            vocabURL = url
        } else {
            let devPath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/vocab.txt")
            if FileManager.default.fileExists(atPath: devPath.path) {
                vocabURL = devPath
            } else {
                throw NRError.vocabNotFound
            }
        }
        guard let content = try? String(contentsOf: vocabURL, encoding: .utf8) else {
            throw NRError.vocabNotFound
        }
        vocab = Self.parseVocab(content)

        outputName = model.modelDescription.outputDescriptionsByName.keys.first
            ?? model.modelDescription.predictedFeatureName
            ?? "logits"
    }

    private static func parseVocab(_ content: String) -> [String: Int] {
        var dict = [String: Int]()
        for (i, line) in content.components(separatedBy: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { dict[t] = i }
        }
        return dict
    }

    func extractPersonNames(from text: String) -> [String] {
        let chars = Array(text)
        var names = Set<String>()
        var start = 0

        while start < chars.count {
            let end = min(start + maxLen, chars.count)
            let chunk = String(chars[start..<end])
            guard let tokenIds = tokenize(chunk) else { start = end; continue }

            let seqLen = tokenIds.count
            guard let inputIds = try? MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32),
                  let mask = try? MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32) else {
                start = end; continue
            }
            for i in 0..<seqLen {
                inputIds[i] = NSNumber(value: tokenIds[i])
                mask[i] = 1
            }

            guard let output = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: inputIds),
                "attention_mask": MLFeatureValue(multiArray: mask)
            ])),
            let logits = output.featureValue(for: outputName)?.multiArrayValue else {
                start = end; continue
            }

            let numLabels = logits.shape.count >= 3 ? logits.shape[2].intValue : 73
            var labels = [Int]()
            for i in 1...seqLen - 2 {
                var best = (label: 0, score: -Double.infinity)
                for j in 0..<numLabels {
                    let score = logits[[0, i, j] as [NSNumber]].doubleValue
                    if score > best.score { best = (j, score) }
                }
                labels.append(best.label)
            }

            var idx = 0
            while idx < labels.count {
                let label = labels[idx]
                if label == 14 {
                    var nameChars = [chars[start + idx]]
                    idx += 1
                    while idx < labels.count && labels[idx] == 32 {
                        nameChars.append(chars[start + idx])
                        idx += 1
                    }
                    if idx < labels.count && labels[idx] == 50 {
                        nameChars.append(chars[start + idx])
                        idx += 1
                    }
                    if nameChars.count >= 2 {
                        names.insert(String(nameChars))
                    }
                } else if label == 68 {
                    let name = String(chars[start + idx])
                    if name.count >= 2 { names.insert(name) }
                    idx += 1
                } else {
                    idx += 1
                }
            }

            start = end - overlap
            if start + maxLen >= chars.count { break }
        }

        return names.sorted { $0.count > $1.count }
    }

    private func tokenize(_ text: String) -> [Int]? {
        let cls = vocab["[CLS]"] ?? 101
        let sep = vocab["[SEP]"] ?? 102
        let unk = vocab["[UNK]"] ?? 100
        var ids = [cls]
        for ch in text {
            ids.append(vocab[String(ch)] ?? unk)
            if ids.count > maxLen { return nil }
        }
        ids.append(sep)
        return ids
    }
}

enum NRError: Error, CustomStringConvertible {
    case modelNotFound, vocabNotFound, inferenceFailed(String)

    var description: String {
        switch self {
        case .modelNotFound: return "NER 模型未找到"
        case .vocabNotFound: return "NER 词表未找到"
        case .inferenceFailed(let m): return "NER 推理失败: \(m)"
        }
    }
}
