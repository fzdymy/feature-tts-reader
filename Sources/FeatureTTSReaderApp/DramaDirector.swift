import Foundation

@MainActor
final class DramaDirector {
    struct ContextWindow {
        let previousDialogue: SentenceContext?
        let upcomingSentences: [SentenceContext]
        let lastSpeakerID: UUID?
        let lastEmotionTag: String?
        let paragraphIndex: Int
        let totalParagraphs: Int
    }

    struct SentenceContext {
        let text: String
        let speakerID: UUID?
        let emotionTag: String
        let isNarrator: Bool
        let speed: Float
        let pitch: Float
        let paragraphIndex: Int
    }

    struct CosyVoiceConfig: Sendable {
        let emotionTag: String
        let speed: Float
        let pitch: Float
        let breathIntensity: Float
    }

    private let narratorEmotionInheritanceRatio: Float = 0.3
    private let sameSpeakerEmotionBlendFactor: Float = 0.6
    private let tensionEscalationThreshold: Int = 2

    func contextualize(_ unit: SentenceUnit, context: ContextWindow) -> SentenceUnit {
        var tag = unit.emotionTag
        var speed = unit.estimatedSpeed
        var pitch = unit.estimatedPitch

        // Rule 1: Narrator inherits 30% emotion tail from preceding dialogue
        if unit.speakerID == nil, let prevDialogue = context.previousDialogue {
            tag = blendEmotionTags(tag, prevDialogue.emotionTag, ratio: narratorEmotionInheritanceRatio)
            speed = lerp(speed, prevDialogue.speed, narratorEmotionInheritanceRatio)
            pitch = lerp(pitch, prevDialogue.pitch, narratorEmotionInheritanceRatio)
        }

        // Rule 2: Pre-judgment tension — upcoming climax within 2 paragraphs
        if context.upcomingClimaxWithin(paragraphs: tensionEscalationThreshold) {
            tag = escalateEmotionTag(tag, toward: "tension")
            speed = min(speed * 1.05, 1.3)
        }

        // Rule 3: Same speaker consecutive — smooth emotion interpolation
        if let speakerID = unit.speakerID,
           speakerID == context.lastSpeakerID,
           let lastTag = context.lastEmotionTag {
            tag = interpolateEmotionTag(lastTag, tag, factor: sameSpeakerEmotionBlendFactor)
            speed = lerp(speed, context.lastSpeakerID != nil ? 1.0 : speed, sameSpeakerEmotionBlendFactor)
        }

        return SentenceUnit(
            text: unit.text,
            speakerID: unit.speakerID,
            emotionTag: tag,
            anchor: unit.anchor,
            estimatedDuration: unit.estimatedDuration,
            estimatedSpeed: speed,
            estimatedPitch: pitch
        )
    }

    private func blendEmotionTags(_ current: String, _ previous: String, ratio: Float) -> String {
        // Narrator inherits preceding dialogue's emotion unless current is already expressive
        let neutralEmotions: Set<String> = ["neutral", "平静", "neutral", "calm"]
        if neutralEmotions.contains(current), !neutralEmotions.contains(previous) {
            return previous
        }
        return ratio > 0.5 ? previous : current
    }

    private func escalateEmotionTag(_ current: String, toward target: String) -> String {
        let tensionTags = ["tension", "fear", "anger", "surprise"]
        if tensionTags.contains(current) { return current }
        return target
    }

    private func interpolateEmotionTag(_ from: String, _ to: String, factor: Float) -> String {
        // Same-speaker smoothing: bias toward established emotion, but accept new expressive tags
        if from == "neutral" || from == "平静" { return to }
        if to == "neutral" || to == "平静" { return from }
        return factor > 0.5 ? from : to
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}

extension DramaDirector.ContextWindow {
    func upcomingClimaxWithin(paragraphs: Int) -> Bool {
        // Check if any upcoming sentence has high-tension keywords
        let tensionKeywords = ["高潮", "危机", "生死", "绝境", "决战", "爆发", "崩溃"]
        for sentence in upcomingSentences {
            if sentence.paragraphIndex - paragraphIndex <= paragraphs {
                if tensionKeywords.contains(where: sentence.text.contains) {
                    return true
                }
            }
        }
        return false
    }
}

struct SentenceUnit: Sendable {
    let text: String
    let speakerID: UUID?
    let emotionTag: String
    let anchor: PlaybackAnchor
    let estimatedDuration: TimeInterval
    let estimatedSpeed: Float
    let estimatedPitch: Float

    init(
        text: String,
        speakerID: UUID?,
        emotionTag: String,
        anchor: PlaybackAnchor,
        estimatedDuration: TimeInterval,
        estimatedSpeed: Float = 1.0,
        estimatedPitch: Float = 1.0
    ) {
        self.text = text
        self.speakerID = speakerID
        self.emotionTag = emotionTag
        self.anchor = anchor
        self.estimatedDuration = estimatedDuration
        self.estimatedSpeed = estimatedSpeed
        self.estimatedPitch = estimatedPitch
    }

    func withEmotionTag(_ tag: String) -> SentenceUnit {
        SentenceUnit(
            text: text,
            speakerID: speakerID,
            emotionTag: tag,
            anchor: anchor,
            estimatedDuration: estimatedDuration,
            estimatedSpeed: estimatedSpeed,
            estimatedPitch: estimatedPitch
        )
    }
}