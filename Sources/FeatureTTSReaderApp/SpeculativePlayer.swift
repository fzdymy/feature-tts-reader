import Foundation

/// 投机播放器：用旁白音色预先合成一段文本，让用户零等待听到声音
actor SpeculativePlayer {
    private var placeholderID: UUID?
    private var pendingReplace: (id: UUID, realSegments: [AISegment], realItems: [TTSQueueItem])?
    private var placeholderState: PlaceholderState = .none

    enum PlaceholderState {
        case none
        case playing(id: UUID)
        case finished(id: UUID)
    }

    /// 用旁白音色合成投机段
    /// - Parameter text: 文本内容（通常为第一个自然段，100~500 字）
    func synthesizePlaceholder(text: String, narratorVoice: String, serverID: UUID, rate: Double = 0, pitch: Double = 0) async -> TTSQueueItem? {
        guard !text.isEmpty, !narratorVoice.isEmpty else { return nil }

        do {
            let audioData = try await EdgeTTSService.shared.synthesize(
                text: text, voice: narratorVoice,
                rate: rate, pitch: pitch,
                style: "neutral", volume: "0dB", serverID: serverID
            )
            let seg = ScriptSegment(
                id: UUID(), characterName: "旁白",
                voice: narratorVoice, rate: Int(rate), pitch: Int(pitch),
                style: "neutral", text: text,
                emotionTag: "neutral", paragraphIndex: 0
            )
            let item = TTSQueueItem(
                id: UUID(), segment: seg, audioURL: nil, audioData: audioData,
                chapterTitle: "", bookTitle: "", bookID: "",
                chapterIndex: 0, segmentIndex: 0, totalSegments: 1,
                paragraphIndex: 0, sentenceIndex: nil, anchor: nil
            )
            placeholderID = item.id
            placeholderState = .playing(id: item.id)
            return item
        } catch {
            return nil
        }
    }

    /// 标记待替换（AI 返回时调用）
    func markPendingReplace(realSegments: [AISegment], realItems: [TTSQueueItem]) {
        guard let pid = placeholderID else { return }
        pendingReplace = (pid, realSegments, realItems)
        // 如果已播完，立即执行替换
        if case .finished(let id) = placeholderState, id == pid {
            pendingReplace = nil
            placeholderID = nil
            placeholderState = .none
        }
    }

    /// 投机段已播完回调
    func onPlaceholderFinished() {
        guard let pid = placeholderID else { return }
        if let pending = pendingReplace, pending.id == pid {
            // 已准备好替换，立即执行
            pendingReplace = nil
            placeholderID = nil
            placeholderState = .none
        } else {
            placeholderState = .finished(id: pid)
        }
    }

    /// 是否有待替换的项
    func hasPendingReplace() -> (id: UUID, items: [TTSQueueItem])? {
        guard let pending = pendingReplace else { return nil }
        return (pending.id, pending.realItems)
    }

    /// 清除状态
    func reset() {
        placeholderID = nil
        pendingReplace = nil
        placeholderState = .none
    }
}
