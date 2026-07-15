import Foundation

/// Tracks speculative (placeholder) vs real segment state for reader playback.
actor SpeculativePlayer {
    enum State {
        case idle
        /// Playing speculative narrator audio for first paragraph
        case speculative(paragraphIndex: Int)
        /// Real AI segments have arrived; speculative item may still be playing
        case realArrived
    }

    private(set) var state: State = .idle
    private var speculativeParagraphIndex: Int?

    /// Mark that speculative playback has started for the given paragraph
    func startSpeculative(paragraphIndex: Int) {
        state = .speculative(paragraphIndex: paragraphIndex)
        speculativeParagraphIndex = paragraphIndex
    }

    /// Called when real AI segments arrive. Returns the paragraph index that was speculatively played.
    /// Also returns whether speculative item is still in queue (not yet played)
    func realSegmentsArrived() -> (index: Int?, wasPlaying: Bool) {
        let idx = speculativeParagraphIndex
        let wasPlaying = isSpeculative
        state = .realArrived
        speculativeParagraphIndex = nil
        return (idx, wasPlaying)
    }

    /// Whether we're still in speculative mode (first segment still playing)
    var isSpeculative: Bool {
        if case .speculative = state { return true }
        return false
    }

    /// Reset to idle
    func reset() {
        state = .idle
        speculativeParagraphIndex = nil
    }

    /// Synthesize a placeholder segment with narrator voice for immediate playback.
    /// Returns a TTSQueueItem ready for immediate queueing, or nil on failure.
    func synthesizePlaceholder(
        text: String,
        narratorVoice: String,
        serverID: UUID?
    ) async -> TTSQueueItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            let audioData = try await EdgeTTSService.shared.synthesize(
                text: trimmed,
                voice: narratorVoice,
                rate: 0,
                pitch: 0,
                style: "neutral",
                volume: "default",
                serverID: serverID
            )

            let scriptSeg = ScriptSegment(
                id: UUID(),
                characterName: "旁白",
                voice: narratorVoice,
                rate: 0,
                pitch: 0,
                style: "neutral",
                text: trimmed,
                emotionTag: "neutral",
                paragraphIndex: 0
            )

            let anchor = PlaybackAnchor(
                bookID: "",
                chapterIndex: 0,
                paragraphIndex: 0,
                sentenceIndex: 0,
                speakerID: nil
            )

            return TTSQueueItem(
                segment: scriptSeg,
                audioURL: nil,
                audioData: audioData,
                chapterTitle: "",
                bookTitle: "",
                bookID: "",
                chapterIndex: 0,
                segmentIndex: 0,
                totalSegments: 1,
                paragraphIndex: 0,
                sentenceIndex: nil,
                anchor: anchor
            )
        } catch {
            return nil
        }
    }
}
