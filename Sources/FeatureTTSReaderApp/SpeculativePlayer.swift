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
    func realSegmentsArrived() -> Int? {
        let idx = speculativeParagraphIndex
        state = .realArrived
        speculativeParagraphIndex = nil
        return idx
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
}
