//
//  SpeechManager.swift
//  ClaudeIsland
//
//  Text-to-speech using macOS AVSpeechSynthesizer
//

import AVFoundation
import Combine
import Foundation
import os.log

@MainActor
class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()

    private static let logger = Logger(subsystem: "com.claudeisland", category: "Speech")

    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking: Bool = false

    /// Track the last spoken message ID to avoid repeats
    private var lastSpokenMessageId: String?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speak the given text, stopping any current speech first
    /// Set `force` to true to bypass the readAloudEnabled check (for on-demand playback)
    func speak(_ text: String, messageId: String? = nil, force: Bool = false) {
        // Skip if we already spoke this message
        if let messageId, messageId == lastSpokenMessageId { return }
        if let messageId { lastSpokenMessageId = messageId }

        guard force || AppSettings.readAloudEnabled else { return }

        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Strip markdown formatting for cleaner speech
        let cleanText = stripMarkdown(text)
        guard !cleanText.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Use the selected voice, or system default
        if let voiceId = AppSettings.selectedVoiceId,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            // Default to a good English voice
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        isSpeaking = true
        synthesizer.speak(utterance)
        Self.logger.debug("Speaking text (\(cleanText.count) chars)")
    }

    /// Stop speaking immediately
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// Available voices for the current locale
    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { a, b in
                // Premium/enhanced voices first, then by name
                if a.quality != b.quality {
                    return a.quality.rawValue > b.quality.rawValue
                }
                return a.name < b.name
            }
    }

    // MARK: - Markdown Stripping

    private func stripMarkdown(_ text: String) -> String {
        var result = text

        // Remove code blocks
        result = result.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove inline code
        result = result.replacingOccurrences(
            of: "`[^`]+`",
            with: "",
            options: .regularExpression
        )

        // Remove headers
        result = result.replacingOccurrences(
            of: "^#{1,6}\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove bold/italic markers
        result = result.replacingOccurrences(
            of: "[*_]{1,3}",
            with: "",
            options: .regularExpression
        )

        // Remove links [text](url) -> text
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )

        // Remove bullet points
        result = result.replacingOccurrences(
            of: "(?m)^[\\s]*[-*+]\\s+",
            with: "",
            options: .regularExpression
        )

        // Collapse whitespace
        result = result.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
