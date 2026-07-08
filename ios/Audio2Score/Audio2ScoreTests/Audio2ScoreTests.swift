//
//  Audio2ScoreTests.swift
//  Audio2ScoreTests
//
//  Created by richie on 7/8/26.
//

import Foundation
import Testing
@testable import Audio2Score

final class TestBundleMarker {}

struct Audio2ScoreTests {
    @Test func decodesDemoTranscription() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try TranscriptionLoader.loadDemo(from: bundle)

        #expect(transcription.engine == "dsp_v0")
        #expect(transcription.keyGuess == "C major")
        #expect(transcription.tempoBpm == 120)
        #expect(transcription.noteEvents.count == 8)
        #expect(transcription.noteEvents.first?.pitchMidi == 60)
    }
}
