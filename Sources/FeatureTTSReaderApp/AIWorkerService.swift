import Foundation

/// AI Worker 服务：切片 -> 请求 Worker -> 合并返回
@MainActor
final class AIWorkerService {
    static let shared = AIWorkerService()

    private init() {}

    /// 处理整章文本，返回剧本片段数组
    func processChapter(
        text: String,
        config: AIWorkerConfig,
        progress: (@Sendable (Double, String) async -> Void)? = nil
    ) async throws -> [AISegment] {
        let slices = sliceText(text, maxChars: config.sliceCharLimit)
        var allSegments: [AISegment] = []
        var context: String? = nil

        DebugLogger.log(flow: "ai_worker", step: "processChapter_start", details: [
            "original_text_length": text.count,
            "original_text_preview": String(text.prefix(200)),
            "slices_count": slices.count,
            "worker_name": config.name,
            "worker_url": config.baseURL,
            "slice_char_limit": config.sliceCharLimit,
        ])

        for (idx, slice) in slices.enumerated() {
            await progress?(Double(idx) / Double(slices.count), "正在解析第 \(idx + 1)/\(slices.count) 片...")

            let request = AIWorkerRequest(
                text: slice,
                sliceIndex: idx,
                totalSlices: slices.count,
                context: context
            )

            let response = try await sendRequest(request, config: config)
            allSegments.append(contentsOf: response.segments)
            context = response.nextContext
        }

        DebugLogger.log(flow: "ai_worker", step: "processChapter_end", details: [
            "total_segments": allSegments.count,
            "segments_preview": allSegments.prefix(5).map { s in
                ["speaker": s.speaker, "emotion": s.emotion.rawValue, "text_preview": String(s.text.prefix(80))]
            },
        ])

        await progress?(1.0, "解析完成，共 \(allSegments.count) 个片段")
        return allSegments
    }

    /// 测试 Worker 连通性
    func testConnection(config: AIWorkerConfig) async throws -> Bool {
        let testText = "测试文本。"
        let request = AIWorkerRequest(text: testText, sliceIndex: 0, totalSlices: 1, context: nil)
        _ = try await sendRequest(request, config: config)
        return true
    }

    // MARK: - Private

    private func sliceText(_ text: String, maxChars: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var slices: [String] = []
        var currentSlice = ""

        for para in paragraphs {
            // 如果当前段落加上新段落超过限制，且当前切片非空，则切分
            if currentSlice.count + para.count > maxChars && !currentSlice.isEmpty {
                slices.append(currentSlice.trimmingCharacters(in: .whitespacesAndNewlines))
                currentSlice = para
            } else {
                if !currentSlice.isEmpty { currentSlice += "\n" }
                currentSlice += para
            }
        }

        if !currentSlice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            slices.append(currentSlice.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 兜底：单个段落超长时强制按字符切分
        return slices.flatMap { slice in
            if slice.count <= maxChars { return [slice] }
            var chunks: [String] = []
            var remaining = slice
            while remaining.count > maxChars {
                let cutIndex = remaining.index(remaining.startIndex, offsetBy: maxChars)
                // 尝试在句号/换行处断开
                let searchRange = remaining.startIndex..<cutIndex
                if let lastPunct = remaining[searchRange].lastIndex(where: { "。！？\n".contains($0) }) {
                    let end = remaining.index(after: lastPunct)
                    chunks.append(String(remaining[..<end]))
                    remaining = String(remaining[end...])
                } else {
                    chunks.append(String(remaining[..<cutIndex]))
                    remaining = String(remaining[cutIndex...])
                }
            }
            if !remaining.isEmpty { chunks.append(remaining) }
            return chunks
        }
    }

    private func sendRequest(_ request: AIWorkerRequest, config: AIWorkerConfig) async throws -> AIWorkerResult {
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            DebugLogger.log(flow: "ai_worker", step: "sendRequest_invalidURL", details: ["url": config.baseURL])
            throw AIWorkerError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.authKey, forHTTPHeaderField: "X-Auth-Key")
        urlRequest.timeoutInterval = config.timeout

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        DebugLogger.log(flow: "ai_worker", step: "sendRequest_outgoing", details: [
            "url": url.absoluteString,
            "method": "POST",
            "headers": [
                "Content-Type": "application/json",
                "X-Auth-Key": config.authKey.isEmpty ? "(empty)" : "***\(config.authKey.suffix(4))",
            ],
            "body": [
                "text_preview": String(request.text.prefix(300)),
                "text_length": request.text.count,
                "slice_index": request.sliceIndex,
                "total_slices": request.totalSlices,
                "has_context": request.context != nil,
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLogger.log(flow: "ai_worker", step: "sendRequest_invalidResponse", details: [
                "url": url.absoluteString,
            ])
            throw AIWorkerError.invalidResponse
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "(binary)"
        DebugLogger.log(flow: "ai_worker", step: "sendRequest_response", details: [
            "url": url.absoluteString,
            "status_code": httpResponse.statusCode,
            "response_body_preview": String(responseBody.prefix(500)),
            "response_body_length": responseBody.count,
        ])

        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                let result = try decoder.decode(AIWorkerResult.self, from: data)
                DebugLogger.log(flow: "ai_worker", step: "sendRequest_decoded", details: [
                    "format": "AIWorkerResult",
                    "segments_count": result.segments.count,
                    "has_next_context": result.nextContext != nil,
                    "segments_preview": result.segments.prefix(5).map { s in
                        ["speaker": s.speaker, "emotion": s.emotion.rawValue, "text_preview": String(s.text.prefix(80))]
                    },
                ])
                return result
            } catch {
                let segments = try decoder.decode([AISegment].self, from: data)
                DebugLogger.log(flow: "ai_worker", step: "sendRequest_decoded", details: [
                    "format": "raw_array",
                    "segments_count": segments.count,
                    "segments_preview": segments.prefix(5).map { s in
                        ["speaker": s.speaker, "emotion": s.emotion.rawValue, "text_preview": String(s.text.prefix(80))]
                    },
                ])
                return AIWorkerResult(segments: segments, nextContext: nil)
            }
        case 401:
            DebugLogger.log(flow: "ai_worker", step: "sendRequest_unauthorized", details: [
                "url": url.absoluteString,
                "auth_key_preview": "***\(config.authKey.suffix(4))",
            ])
            throw AIWorkerError.unauthorized
        case 429:
            DebugLogger.log(flow: "ai_worker", step: "sendRequest_rateLimited")
            throw AIWorkerError.rateLimited
        default:
            let errorMsg = String(data: data, encoding: .utf8) ?? "未知错误"
            DebugLogger.log(flow: "ai_worker", step: "sendRequest_error", details: [
                "url": url.absoluteString,
                "status_code": httpResponse.statusCode,
                "error_body": String(errorMsg.prefix(500)),
            ])
            throw AIWorkerError.serverError(httpResponse.statusCode, errorMsg)
        }
    }
}

enum AIWorkerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int, String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Worker URL 格式错误"
        case .invalidResponse: return "服务器响应格式错误"
        case .unauthorized: return "认证失败，请检查 Auth Key"
        case .rateLimited: return "请求过于频繁，请稍后重试"
        case .serverError(let code, let msg): return "Worker 错误 \(code): \(msg)"
        case .decodingFailed(let e): return "解析失败: \(e.localizedDescription)"
        }
    }
}