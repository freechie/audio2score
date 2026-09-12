import CoreGraphics
import Foundation
import Testing
@testable import OpenBard

final class TestBundleMarker {}

struct OpenBardTests {
    @Test func decodesDemoTranscription() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try TranscriptionLoader.loadDemo(from: bundle)

        #expect(transcription.engine == "dsp_v0")
        #expect(transcription.keyGuess == "C major")
        #expect(transcription.tempoBpm == 120)
        #expect(transcription.noteEvents.count == 3)
        #expect(transcription.noteEvents.map(\.pitchMidi) == [60, 64, 67])
        #expect(transcription.noteEvents.allSatisfy { $0.onsetSeconds == 0 })
        #expect(transcription.noteEvents.allSatisfy { $0.durationSeconds == 2 })
    }

    @Test func demoAudioIsBundled() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let url = try TranscriptionLoader.demoAudioURL(from: bundle)
        let data = try Data(contentsOf: url)

        #expect(url.lastPathComponent == "c-major-chord.wav")
        #expect(data.starts(with: Data("RIFF".utf8)))
    }
    
    @Test func fixtureAudioIsBundled() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        
        for fixture in AudioFixture.allCases {
            let url = try TranscriptionLoader.fixtureAudioURL(fixture, from: bundle)
            let data = try Data(contentsOf: url)
            
            #expect(url.lastPathComponent.hasSuffix(".wav"))
            #expect(data.starts(with: Data("RIFF".utf8)))
        }
    }
    
    @Test func fixtureGroundTruthLoads() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        
        let isolatedPianoTranscription = try TranscriptionLoader.loadFixture(.isolatedPiano, from: bundle)
        #expect(isolatedPianoTranscription != nil)
        #expect(isolatedPianoTranscription?.noteEvents.count == 21)
        
        let mixedTranscription = try TranscriptionLoader.loadFixture(.mixedArrangement, from: bundle)
        #expect(mixedTranscription != nil)
        #expect(mixedTranscription?.noteEvents.count == 37)
        
        let cMajorTranscription = try TranscriptionLoader.loadFixture(.cMajorChord, from: bundle)
        #expect(cMajorTranscription == nil)
    }

    @Test func pianoRollStacksChordNotes() {
        let notes = [
            NoteEvent(
                pitchMidi: 60,
                onsetSeconds: 0,
                durationSeconds: 2,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            ),
            NoteEvent(
                pitchMidi: 64,
                onsetSeconds: 0,
                durationSeconds: 2,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            ),
            NoteEvent(
                pitchMidi: 67,
                onsetSeconds: 0,
                durationSeconds: 2,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble
            ),
        ]
        let frames = PianoRollLayout.frames(
            notes: notes,
            in: CGSize(width: 200, height: 100)
        )

        #expect(frames.count == 3)
        #expect(frames[0].minX == frames[1].minX)
        #expect(frames[0].minX == frames[2].minX)
        #expect(frames[2].minY < frames[1].minY)
        #expect(frames[1].minY < frames[0].minY)
    }
    
    @Test func splitNoteAtMidpoint() {
        let note = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 1.0,
            durationSeconds: 2.0,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble
        )
        
        let result = NoteHelpers.splitNote(note)
        #expect(result != nil)
        
        let (first, second) = result!
        #expect(first.pitchMidi == 60)
        #expect(first.onsetSeconds == 1.0)
        #expect(first.durationSeconds == 1.0)
        #expect(second.onsetSeconds == 2.0)
        #expect(second.durationSeconds == 1.0)
        #expect(!first.isLocked && !second.isLocked)
    }
    
    @Test func splitRejectsShortNotes() {
        let shortNote = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 0.05,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble
        )
        
        #expect(NoteHelpers.splitNote(shortNote) == nil)
    }
    
    @Test func splitWorksEvenIfLegacyLockFlagSet() {
        let lockedNote = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 2.0,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble,
            isLocked: true
        )

        let split = NoteHelpers.splitNote(lockedNote)
        #expect(split != nil)
        #expect(split!.0.durationSeconds == 1.0)
    }
    
    @Test func mergeAdjacentNotes() {
        let note1 = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 1.0,
            velocity: 0.8,
            confidence: 0.9,
            staffHint: .treble
        )
        let note2 = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 1.0,
            durationSeconds: 1.0,
            velocity: 0.7,
            confidence: 0.85,
            staffHint: .treble
        )
        
        let merged = NoteHelpers.mergeNotes(note1, note2)
        #expect(merged != nil)
        #expect(merged!.pitchMidi == 60)
        #expect(merged!.onsetSeconds == 0)
        #expect(merged!.durationSeconds == 2.0)
        #expect(merged!.velocity == 0.8)
        #expect(merged!.confidence == 0.9)
        #expect(!merged!.isLocked)
    }
    
    @Test func mergeRejectsDifferentPitches() {
        let note1 = NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let note2 = NoteEvent(pitchMidi: 64, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        
        #expect(NoteHelpers.mergeNotes(note1, note2) == nil)
    }
    
    @Test func mergeWorksEvenIfLegacyLockFlagSet() {
        let note1 = NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble, isLocked: true)
        let note2 = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)

        let merged = NoteHelpers.mergeNotes(note1, note2)
        #expect(merged != nil)
        #expect(merged!.durationSeconds == 2.0)
    }
    
    @Test func nudgeAdjustsTiming() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: 0.5, pitchOffset: 0)
        
        #expect(nudged != nil)
        #expect(nudged!.onsetSeconds == 1.5)
        #expect(nudged!.pitchMidi == 60)
    }
    
    @Test func nudgeAdjustsPitch() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: 0, pitchOffset: 2)
        
        #expect(nudged != nil)
        #expect(nudged!.onsetSeconds == 1.0)
        #expect(nudged!.pitchMidi == 62)
    }
    
    @Test func nudgeRejectsInvalidPitch() {
        let note = NoteEvent(pitchMidi: 127, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: 0, pitchOffset: 1)
        
        #expect(nudged == nil)
    }
    
    @Test func nudgeClampsNegativeTime() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 0.5, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        let nudged = NoteHelpers.nudgeNote(note, timeOffset: -1.0, pitchOffset: 0)
        
        #expect(nudged != nil)
        #expect(nudged!.onsetSeconds == 0)
    }

    @Test func pianoRollEditMovesFromSnapshotNotCumulatively() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble)
        let snapshot = PianoRollEdit.snapshot(of: note)
        let scales = PianoRollEdit.Scales(secondsPerPoint: 0.01, rowHeight: 20)

        let moved = PianoRollEdit.movedNote(
            from: snapshot,
            translation: CGSize(width: 50, height: -20),
            scales: scales,
            base: note
        )

        #expect(moved != nil)
        #expect(moved!.onsetSeconds == 1.5)
        #expect(moved!.pitchMidi == 61)

        // Same translation again from snapshot must yield the same result (not accumulate).
        let again = PianoRollEdit.movedNote(
            from: snapshot,
            translation: CGSize(width: 50, height: -20),
            scales: scales,
            base: moved!
        )
        #expect(again!.onsetSeconds == 1.5)
        #expect(again!.pitchMidi == 61)
    }

    @Test func pianoRollEditResizesDurationFromRightEdge() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble)
        let snapshot = PianoRollEdit.snapshot(of: note)
        let scales = PianoRollEdit.Scales(secondsPerPoint: 0.01, rowHeight: 20)

        let longer = PianoRollEdit.resizedNote(
            from: snapshot,
            translation: CGSize(width: 100, height: 0),
            scales: scales,
            base: note
        )
        #expect(longer!.durationSeconds == 2.0)

        let clamped = PianoRollEdit.resizedNote(
            from: snapshot,
            translation: CGSize(width: -10_000, height: 0),
            scales: scales,
            base: note
        )
        #expect(clamped!.durationSeconds == NoteHelpers.minimumNoteDurationSeconds)
    }

    @Test func pianoRollEditAllowsNotesRegardlessOfLegacyLockFlag() {
        let note = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: 0,
            durationSeconds: 1,
            velocity: 0.8,
            confidence: 1,
            staffHint: .treble,
            isLocked: true
        )
        let snapshot = PianoRollEdit.snapshot(of: note)
        let scales = PianoRollEdit.Scales(secondsPerPoint: 0.01, rowHeight: 20)
        #expect(
            PianoRollEdit.movedNote(
                from: snapshot,
                translation: CGSize(width: 10, height: -20),
                scales: scales,
                base: note
            ) != nil
        )
        #expect(
            PianoRollEdit.resizedNote(
                from: snapshot,
                translation: CGSize(width: 10, height: 0),
                scales: scales,
                base: note
            ) != nil
        )
    }

    @Test func pianoRollEditResizesFromLeftEdge() {
        let note = NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble)
        let snapshot = PianoRollEdit.snapshot(of: note)
        let scales = PianoRollEdit.Scales(secondsPerPoint: 0.01, rowHeight: 20)
        let edited = PianoRollEdit.resizedNoteFromLeft(
            from: snapshot,
            translation: CGSize(width: 50, height: 0),
            scales: scales,
            base: note
        )
        #expect(edited!.onsetSeconds == 1.5)
        #expect(edited!.durationSeconds == 0.5)
        #expect(PianoRollEdit.edgeHit(frame: CGRect(x: 40, y: 10, width: 100, height: 20), point: CGPoint(x: 45, y: 20)) == .left)
    }

    @Test func pianoRollEditDetectsRightEdgeHit() {
        let frame = CGRect(x: 40, y: 10, width: 100, height: 20)
        #expect(PianoRollEdit.isRightEdgeHit(frame: frame, point: CGPoint(x: 135, y: 20)))
        #expect(!PianoRollEdit.isRightEdgeHit(frame: frame, point: CGPoint(x: 60, y: 20)))
    }
    
    @Test func findsMergeCandidate() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble),
            NoteEvent(pitchMidi: 60, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 0.9, staffHint: .treble)
        ]
        
        let candidate = NoteHelpers.findMergeCandidate(for: notes[0], in: notes, currentIndex: 0)
        #expect(candidate == 1)
    }
    
    @Test func pianoRollLabelPositionsMatchFrames() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0.5, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 67, onsetSeconds: 1.0, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let size = CGSize(width: 300, height: 220)
        let viewport = PianoRollViewport.seeded(from: notes, tempoBpm: 120)
        let frames = PianoRollLayout.frames(notes: notes, viewport: viewport, in: size)
        let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)

        for (index, note) in notes.enumerated() {
            let frame = frames[index]
            let expectedCenterY = metrics.contentMinY
                + CGFloat(viewport.maxPitch - note.pitchMidi) * metrics.rowHeight
                + metrics.rowHeight / 2
            #expect(abs(expectedCenterY - frame.midY) < metrics.rowHeight / 2)
            #expect(frame.minY >= metrics.contentMinY - 0.5)
            #expect(frame.maxY <= metrics.velocityMinY + 0.5)
        }
    }

    @Test func pianoRollKeepsIsolatedPianoNotesVisible() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let transcription = try TranscriptionLoader.loadFixture(.isolatedPiano, from: bundle)
        let notes = try #require(transcription?.noteEvents)
        let size = CGSize(width: 320, height: 280)
        let frames = PianoRollLayout.frames(notes: notes, in: size)
        let metrics = PianoRollLayout.metrics(notes: notes, in: size)

        #expect(frames.count == 21)
        #expect(frames.allSatisfy { $0.width >= 2 && $0.height >= 2 })
        #expect(frames.allSatisfy { $0.minY >= metrics.contentMinY - 0.5 && $0.maxY <= metrics.velocityMinY + 0.5 })
    }

    @Test func pianoRollHitTestSelectsPitchRowNotTopNoteEverywhere() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble),
        ]
        let size = CGSize(width: 200, height: 160)
        let frames = PianoRollLayout.frames(notes: notes, in: size)

        #expect(PianoRollLayout.hitTest(notes: notes, at: CGPoint(x: frames[0].midX, y: frames[0].midY), in: size) == 0)
        #expect(PianoRollLayout.hitTest(notes: notes, at: CGPoint(x: frames[1].midX, y: frames[1].midY), in: size) == 1)
        #expect(PianoRollLayout.hitTest(notes: notes, at: CGPoint(x: frames[2].midX, y: frames[2].midY), in: size) == 2)
        #expect(PianoRollLayout.hitTest(notes: notes, at: CGPoint(x: 10, y: 10), in: size) == nil)
    }

    @Test func togglingNoteLockUpdatesTranscription() {
        var transcription = TranscriptionResult(
            engine: "test",
            engineVersion: "0",
            tempoBpm: 120,
            keyGuess: "C",
            noteEvents: [
                NoteEvent(
                    pitchMidi: 60,
                    onsetSeconds: 0,
                    durationSeconds: 1,
                    velocity: 0.8,
                    confidence: 1,
                    staffHint: .treble,
                    isLocked: false
                )
            ]
        )

        transcription.noteEvents[0].isLocked.toggle()
        #expect(transcription.noteEvents[0].isLocked)

        transcription.noteEvents[0].isLocked.toggle()
        #expect(!transcription.noteEvents[0].isLocked)
    }

    @Test func midiExportRequiresNotes() {
        #expect(throws: MIDIExportError.noNotes) {
            try MIDIExporter.makeData(from: [])
        }
    }

    @Test func midiExportWritesFormat0HeaderAndChordPitches() throws {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
        ]

        let data = try MIDIExporter.makeData(from: notes, tempoBpm: 120)
        let bytes = [UInt8](data)

        #expect(String(bytes[0..<4].map { Character(UnicodeScalar($0)) }) == "MThd")
        #expect(bytes[8] == 0 && bytes[9] == 0) // format 0
        #expect(bytes[10] == 0 && bytes[11] == 1) // one track
        #expect(String(bytes[14..<18].map { Character(UnicodeScalar($0)) }) == "MTrk")
        #expect(bytes.contains(0x90))
        #expect(bytes.contains(60))
        #expect(bytes.contains(64))
        #expect(bytes.contains(67))
        #expect(MIDIExporter.vlq(0) == [0x00])
        #expect(MIDIExporter.vlq(127) == [0x7F])
        #expect(MIDIExporter.vlq(128) == [0x81, 0x00])
        #expect(MIDIExporter.midiVelocity(0.8) == 102)
    }

    @Test func musicXMLExportRequiresNotes() {
        #expect(throws: MusicXMLExportError.noScore) {
            try MusicXMLExporter.makeData(from: [])
        }
    }

    @Test func musicXMLExportWritesPartwiseChord() throws {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
        ]

        let data = try MusicXMLExporter.makeData(from: notes)
        let xml = String(decoding: data, as: UTF8.self)

        #expect(xml.contains("score-partwise"))
        #expect(xml.contains("<divisions>4</divisions>"))
        #expect(xml.contains("<sign>G</sign>"))
        #expect(xml.contains("<step>C</step>"))
        #expect(xml.contains("<step>E</step>"))
        #expect(xml.contains("<step>G</step>"))
        #expect(xml.contains("<chord/>"))
        #expect(xml.contains("<per-minute>"))
        #expect(MusicXMLExporter.midiToPitch(61).step == "C")
        #expect(MusicXMLExporter.midiToPitch(61).alter == 1)
        #expect(MusicXMLExporter.noteType(for: 1.0) == "quarter")
        #expect(MusicXMLExporter.noteType(for: 0.25) == "16th")
    }

    @Test func musicXMLExportEmitsTieAcrossBarline() throws {
        let notes = [
            NoteEvent(
                pitchMidi: 60,
                onsetSeconds: 1.5,
                durationSeconds: 1.0,
                velocity: 0.8,
                confidence: 1,
                staffHint: .treble,
                isLocked: true
            )
        ]
        let data = try MusicXMLExporter.makeData(from: notes)
        let xml = String(decoding: data, as: UTF8.self)
        #expect(xml.contains(#"<tie type="start"/>"#))
        #expect(xml.contains(#"<tie type="stop"/>"#))
        #expect(xml.contains("<measure number=\"2\">"))
    }

    @Test func scoreBuilderReturnsNilWithoutNotes() {
        #expect(ScoreBuilder.build(from: []) == nil)
    }

    @Test func scoreBuilderUsesAllNotesWithoutLock() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 72, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let score = ScoreBuilder.build(from: notes, tempoBpm: 120)
        #expect(score != nil)
        let noteCount = score!.measures.flatMap(\.items).filter {
            if case .note = $0 { return true }
            return false
        }.count
        #expect(noteCount == 2)
    }

    @Test func scoreBuilderQuantizesLockedCMajorChordToOneMeasure() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        #expect(score!.tempoBpm == 120)
        #expect(score!.clef == .treble)
        #expect(score!.measures.count == 1)
        let notesInScore = score!.measures[0].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        #expect(notesInScore.map(\.pitchMidi) == [60, 64, 67])
        #expect(notesInScore.allSatisfy { $0.startBeat == 0 && $0.durationBeats == 4 && !$0.tiedToNext })
        #expect(!score!.measures[0].items.contains { if case .rest = $0 { return true }; return false })
    }

    @Test func scoreBuilderInsertsTrailingRestAfterQuarter() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 0.5, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        #expect(score!.measures.count == 1)
        guard case .note(let note) = score!.measures[0].items.first else {
            #expect(Bool(false))
            return
        }
        #expect(note.durationBeats == 1)
        guard case .rest(let rest) = score!.measures[0].items.last else {
            #expect(Bool(false))
            return
        }
        #expect(rest.startBeat == 1)
        #expect(rest.durationBeats == 3)
    }

    @Test func scoreBuilderTiesNoteAcrossBarline() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 1.5, durationSeconds: 1.0, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)
        #expect(score != nil)
        #expect(score!.tempoBpm == 120)
        #expect(score!.measures.count == 2)
        let firstNotes = score!.measures[0].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        let secondNotes = score!.measures[1].items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        #expect(firstNotes.count == 1)
        #expect(firstNotes[0].startBeat == 3)
        #expect(firstNotes[0].durationBeats == 1)
        #expect(firstNotes[0].tiedToNext)
        #expect(secondNotes.count == 1)
        #expect(secondNotes[0].startBeat == 4)
        #expect(secondNotes[0].durationBeats == 1)
        #expect(!secondNotes[0].tiedToNext)
    }

    @Test func musicXMLOverlappingNotesDoNotOverflowTheMeasure() throws {
        let notes = [
            musicNote(pitch: 48, onset: 0, duration: 4),
            musicNote(pitch: 84, onset: 1, duration: 1),
        ]
        let xml = try musicXML(from: notes, tempoBpm: 60)
        let rhythm = MusicXMLRhythm.inspect(xml)
        #expect(rhythm.cursorEnds == [16])
        #expect(rhythm.incompleteVoices == 0)
        #expect(rhythm.mixedDurationChords == 0)
        #expect(xml.contains("<step>C</step>"))
        #expect(xml.contains("<octave>3</octave>"))
        #expect(xml.contains("<octave>6</octave>"))
    }

    @Test func musicXMLMixedDurationChordKeepsTheLongerTone() throws {
        let notes = [
            musicNote(pitch: 48, onset: 0, duration: 0.5),
            musicNote(pitch: 64, onset: 0, duration: 2.0),
        ]
        let xml = try musicXML(from: notes, tempoBpm: 120)
        let rhythm = MusicXMLRhythm.inspect(xml)
        #expect(rhythm.cursorEnds == [16])
        #expect(rhythm.incompleteVoices == 0)
        #expect(rhythm.mixedDurationChords == 0)
        #expect(xml.contains("<octave>3</octave>"))
        #expect(xml.contains("<step>E</step>"))
    }

    @Test func musicXMLGridDurationsMatchDeclaredType() throws {
        var mismatchBeats: [Double] = []
        var unfilledBeats: [Double] = []
        for step in 1...16 {
            let beats = Double(step) * 0.25
            let notes = [musicNote(pitch: 60, onset: 0, duration: beats * 0.5)]
            let xml = try musicXML(from: notes, tempoBpm: 120)
            let rhythm = MusicXMLRhythm.inspect(xml)
            if rhythm.typeMismatches != 0 {
                mismatchBeats.append(beats)
            }
            if rhythm.cursorEnds != [16] || rhythm.incompleteVoices != 0 {
                unfilledBeats.append(beats)
            }
        }
        #expect(mismatchBeats == [])
        #expect(unfilledBeats == [])
    }

    @Test func musicXMLBundledFixturesHaveValidMeasureRhythm() throws {
        let bundle = Bundle(for: TestBundleMarker.self)
        let isolated = try TranscriptionLoader.loadFixture(.isolatedPiano, from: bundle)!
        let mixed = try TranscriptionLoader.loadFixture(.mixedArrangement, from: bundle)!
        let isolatedXML = try musicXML(from: isolated.noteEvents, tempoBpm: isolated.tempoBpm)
        let mixedXML = try musicXML(from: mixed.noteEvents, tempoBpm: mixed.tempoBpm)
        let isolatedRhythm = MusicXMLRhythm.inspect(isolatedXML)
        let mixedRhythm = MusicXMLRhythm.inspect(mixedXML)
        #expect(isolatedRhythm.isValid)
        #expect(mixedRhythm.isValid)
    }

    @Test func zoomMathClampsScale() {
        #expect(ZoomMath.clamp(0) == ZoomMath.minimum)
        #expect(ZoomMath.clamp(1) == 1)
        #expect(ZoomMath.clamp(99) == ZoomMath.maximum)
    }

    @Test func zoomMathScalesContentToViewport() {
        let size = ZoomMath.contentSize(viewport: CGSize(width: 100, height: 50), scale: 2)
        #expect(size.width == 200)
        #expect(size.height == 100)
    }

    @Test func zoomMathClampsPanToScaledExtra() {
        let offset = ZoomMath.clampOffset(
            CGSize(width: 5000, height: -5000),
            viewport: CGSize(width: 100, height: 80),
            scale: 2
        )
        #expect(offset.width == 74)
        #expect(offset.height == -64)
    }

    @Test func staffLineSpacingGrowsWithViewportHeight() {
        let small = StaffLayout.lineSpacing(in: CGSize(width: 320, height: 96))
        let large = StaffLayout.lineSpacing(in: CGSize(width: 320, height: 240))
        #expect(large > small)
        #expect(small >= 8)
    }

    @Test func staffFitKeepsNoteHeadsInsideViewport() {
        let notes = [
            NoteEvent(pitchMidi: 72, onsetSeconds: 0, durationSeconds: 1, velocity: 0.8, confidence: 1, staffHint: .treble, isLocked: true),
            NoteEvent(pitchMidi: 48, onsetSeconds: 0, durationSeconds: 1, velocity: 0.8, confidence: 1, staffHint: .bass, isLocked: true)
        ]
        let score = ScoreBuilder.build(from: notes)!
        let size = CGSize(width: 320, height: 160)
        let fit = StaffLayout.fit(score: score, in: size)
        let head: CGFloat = max(6, fit.lineSpacing * 0.8)
        let highY = fit.bottomLineY
            - CGFloat(StaffLayout.diatonicSteps(72) - StaffLayout.diatonicSteps(64)) * (fit.lineSpacing / 2)
        let lowY = fit.bottomLineY
            - CGFloat(StaffLayout.diatonicSteps(48) - StaffLayout.diatonicSteps(64)) * (fit.lineSpacing / 2)
        #expect(highY - head / 2 >= fit.padding - 0.5)
        #expect(lowY + head / 2 <= size.height - fit.padding + 0.5)
    }

    @Test func pianoRollFramesStayInsideViewport() {
        let notes = [
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 2, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let size = CGSize(width: 300, height: 220)
        let frames = PianoRollLayout.frames(notes: notes, in: size)
        let metrics = PianoRollLayout.metrics(notes: notes, in: size)
        for frame in frames {
            #expect(frame.minX >= PianoRollLayout.labelGutter - 0.1)
            #expect(frame.maxX <= size.width - PianoRollLayout.trailingInset + 0.1)
            #expect(frame.minY >= metrics.contentMinY - 0.1)
            #expect(frame.maxY <= metrics.velocityMinY + 0.1)
        }
    }

    @Test func pianoRollUsesAbletonStyleChromeInsets() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let metrics = PianoRollLayout.metrics(notes: notes, in: CGSize(width: 300, height: 240))
        #expect(metrics.rulerHeight == PianoRollLayout.rulerHeight)
        #expect(metrics.velocityHeight == PianoRollLayout.velocityHeight)
        #expect(metrics.contentMinY >= PianoRollLayout.rulerHeight)
        #expect(PianoRollLayout.isBlackKey(midi: 61))
        #expect(!PianoRollLayout.isBlackKey(midi: 60))
    }

    @Test func pianoRollViewportPadsFixtureAndDoesNotShrink() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 67, onsetSeconds: 1, durationSeconds: 1, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let seeded = PianoRollViewport.seeded(from: notes, tempoBpm: 120)
        #expect(seeded.minPitch == 60 - PianoRollViewport.pitchPadding)
        #expect(seeded.maxPitch == 67 + PianoRollViewport.pitchPadding)
        #expect(seeded.timelineSeconds >= 2 + PianoRollViewport.minTimelinePaddingBeats * 0.5)

        let dragged = NoteEvent(
            pitchMidi: 55,
            onsetSeconds: 0.5,
            durationSeconds: 1,
            velocity: 0.8,
            confidence: 1,
            staffHint: .bass
        )
        let expanded = seeded.expanding(toFit: dragged)
        #expect(expanded.minPitch <= 55)
        #expect(expanded.maxPitch == seeded.maxPitch)
        #expect(expanded.timelineSeconds == seeded.timelineSeconds)

        let later = NoteEvent(
            pitchMidi: 60,
            onsetSeconds: expanded.timelineSeconds + 1,
            durationSeconds: 1,
            velocity: 0.8,
            confidence: 1,
            staffHint: .treble
        )
        let grown = expanded.expanding(toFit: later)
        #expect(grown.timelineSeconds > expanded.timelineSeconds)
        #expect(grown.minPitch == expanded.minPitch)
    }

    @Test func pianoRollBlankViewportDrawsEmptyMetrics() {
        let viewport = PianoRollViewport.blank
        let size = CGSize(width: 300, height: 240)
        let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)
        #expect(metrics.rowHeight > 0)
        #expect(PianoRollLayout.frames(notes: [], viewport: viewport, in: size).isEmpty)
        #expect(viewport.minPitch == 48)
        #expect(viewport.maxPitch == 72)
        #expect(viewport.timelineSeconds == NoteHelpers.barsToSeconds(16, tempoBpm: 120))
    }

    @Test func pianoRollTimeWindowZoomsAndPansWithoutShrinkingContent() {
        var window = PianoRollTimeWindow.blank(tempoBpm: 120)
        let content = window.contentSeconds
        window.zoom(factor: 2, anchorNormalized: 0.5)
        #expect(window.contentSeconds == content)
        #expect(window.visibleDuration < content)
        window.pan(deltaSeconds: 1)
        #expect(window.visibleStart >= 0)
        #expect(window.visibleEnd <= window.contentSeconds + 0.0001)
        window.setHotspot(start: 0, duration: content)
        #expect(abs(window.visibleDuration - content) < 0.0001)
    }

    @Test func pianoRollScalesUseFrozenViewportNotLiveNotes() {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 1, velocity: 0.8, confidence: 1, staffHint: .treble)
        ]
        let viewport = PianoRollViewport(minPitch: 48, maxPitch: 72, timelineSeconds: 8)
        let size = CGSize(width: 300, height: 240)
        let scales = PianoRollEdit.Scales.from(viewport: viewport, size: size)
        let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)

        #expect(abs(scales.secondsPerPoint - (8.0 / Double(metrics.drawableWidth))) < 0.0001)
        #expect(abs(scales.rowHeight - Double(metrics.rowHeight)) < 0.0001)

        // Dragging a note outside the original note range must keep the same scales
        // when the viewport is held fixed (no reflow).
        let scalesAgain = PianoRollEdit.Scales.from(viewport: viewport, size: size)
        #expect(scalesAgain == scales)
        #expect(notes.count == 1)
    }

    @Test func pianoRollMapsPointToPitchAndCreatesDrawnNote() {
        let viewport = PianoRollViewport(minPitch: 48, maxPitch: 72, timelineSeconds: 4)
        let size = CGSize(width: 300, height: 240)
        let metrics = PianoRollLayout.metrics(viewport: viewport, in: size)

        let midPitch = (viewport.minPitch + viewport.maxPitch) / 2
        let row = viewport.maxPitch - midPitch
        let point = CGPoint(
            x: metrics.labelGutter + metrics.drawableWidth * 0.25,
            y: metrics.contentMinY + CGFloat(row) * metrics.rowHeight + metrics.rowHeight / 2
        )

        let mapped = PianoRollEdit.pitchAndOnset(at: point, viewport: viewport, size: size)
        #expect(mapped != nil)
        #expect(mapped!.pitch == midPitch)
        #expect(abs(mapped!.onset - 1.0) < 0.05)

        let note = PianoRollEdit.makeDrawnNote(
            pitch: mapped!.pitch,
            onset: mapped!.onset,
            duration: NoteHelpers.defaultDurationSeconds(tempoBpm: 120)
        )
        #expect(note.pitchMidi == midPitch)
        #expect(note.durationSeconds == 0.125)
        #expect(note.velocity == NoteHelpers.defaultDrawVelocity)
        #expect(note.staffHint == .treble)
        #expect(!note.isLocked)
    }

    @Test func noteAudioRendererRejectsEmptyNotes() {
        #expect(throws: NoteAudioRenderer.RenderError.noNotes) {
            try NoteAudioRenderer.makeWAVData(from: [])
        }
    }

    @Test func noteAudioRendererWritesWavHeaderAndChordEnergy() throws {
        let notes = [
            NoteEvent(pitchMidi: 60, onsetSeconds: 0, durationSeconds: 0.5, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 64, onsetSeconds: 0, durationSeconds: 0.5, velocity: 0.8, confidence: 1, staffHint: .treble),
            NoteEvent(pitchMidi: 67, onsetSeconds: 0, durationSeconds: 0.5, velocity: 0.8, confidence: 1, staffHint: .treble),
        ]
        let data = try NoteAudioRenderer.makeWAVData(from: notes)
        let bytes = [UInt8](data)
        #expect(String(bytes[0..<4].map { Character(UnicodeScalar($0)) }) == "RIFF")
        #expect(String(bytes[8..<12].map { Character(UnicodeScalar($0)) }) == "WAVE")
        #expect(data.count > 44)
        #expect(abs(NoteAudioRenderer.frequency(midiPitch: 69) - 440) < 0.01)
        #expect(NoteAudioRenderer.timelineEnd(notes: notes) == 0.5)
    }
}

private func musicNote(pitch: Int, onset: Double, duration: Double) -> NoteEvent {
    NoteEvent(
        pitchMidi: pitch,
        onsetSeconds: onset,
        durationSeconds: duration,
        velocity: 0.8,
        confidence: 1,
        staffHint: .treble,
        isLocked: true
    )
}

private func musicXML(from notes: [NoteEvent], tempoBpm: Double?) throws -> String {
    let data = try MusicXMLExporter.makeData(from: notes, tempoBpm: tempoBpm)
    return String(decoding: data, as: UTF8.self)
}

private struct MusicXMLRhythm {
    var cursorEnds: [Int]
    var typeMismatches: Int
    var mixedDurationChords: Int
    var incompleteVoices: Int
    var expectedDivisions: Int

    var isValid: Bool {
        typeMismatches == 0
            && mixedDurationChords == 0
            && incompleteVoices == 0
            && cursorEnds.allSatisfy { $0 == expectedDivisions }
    }

    static func inspect(_ xml: String) -> MusicXMLRhythm {
        let divisions = firstIntTag("divisions", in: xml) ?? MusicXMLExporter.divisionsPerQuarter
        let expected = 4 * divisions
        var cursorEnds: [Int] = []
        var typeMismatches = 0
        var mixedDurationChords = 0
        var incompleteVoices = 0

        for measure in elements(named: "measure", in: xml) {
            var cursor = 0
            var voiceSums: [String: Int] = [:]
            var anchorDuration: Int?
            var index = measure.startIndex
            while index < measure.endIndex {
                guard let event = nextTimedEvent(in: measure, from: index) else { break }
                index = event.end
                switch event.kind {
                case .backup(let duration):
                    cursor -= duration
                case .forward(let duration):
                    cursor += duration
                case .note(let body):
                    let duration = firstIntTag("duration", in: body) ?? 0
                    let voice = firstStringTag("voice", in: body) ?? "1"
                    let isChord = body.contains("<chord/>") || body.contains("<chord />")
                    let isGrace = body.contains("<grace")
                    let dots = dotCount(in: body)
                    if let type = firstStringTag("type", in: body),
                       let implied = impliedDivisions(type: type, dots: dots, divisions: divisions),
                       implied != duration {
                        typeMismatches += 1
                    }
                    if isChord {
                        if let anchorDuration, duration != anchorDuration {
                            mixedDurationChords += 1
                        }
                    } else {
                        anchorDuration = duration
                    }
                    if isGrace {
                        continue
                    }
                    if !isChord {
                        cursor += duration
                        voiceSums[voice, default: 0] += duration
                    }
                }
            }
            cursorEnds.append(cursor)
            if voiceSums.values.contains(where: { $0 != expected }) {
                incompleteVoices += 1
            }
        }

        return MusicXMLRhythm(
            cursorEnds: cursorEnds,
            typeMismatches: typeMismatches,
            mixedDurationChords: mixedDurationChords,
            incompleteVoices: incompleteVoices,
            expectedDivisions: expected
        )
    }
}

private struct TimedEvent {
    enum Kind {
        case note(String)
        case backup(Int)
        case forward(Int)
    }

    var kind: Kind
    var end: String.Index
}

private func nextTimedEvent(in text: String, from index: String.Index) -> TimedEvent? {
    let note = text.range(of: "<note", range: index..<text.endIndex)
    let backup = text.range(of: "<backup", range: index..<text.endIndex)
    let forward = text.range(of: "<forward", range: index..<text.endIndex)
    let candidates: [(String, Range<String.Index>)] = [
        note.map { ("note", $0) },
        backup.map { ("backup", $0) },
        forward.map { ("forward", $0) },
    ].compactMap { $0 }
    guard let earliest = candidates.min(by: { $0.1.lowerBound < $1.1.lowerBound }) else {
        return nil
    }
    let name = earliest.0
    let start = earliest.1.lowerBound
    let close = "</\(name)>"
    guard let end = text.range(of: close, range: start..<text.endIndex) else {
        return nil
    }
    let body = String(text[start..<end.upperBound])
    switch name {
    case "note":
        return TimedEvent(kind: .note(body), end: end.upperBound)
    case "backup":
        return TimedEvent(kind: .backup(firstIntTag("duration", in: body) ?? 0), end: end.upperBound)
    case "forward":
        return TimedEvent(kind: .forward(firstIntTag("duration", in: body) ?? 0), end: end.upperBound)
    default:
        return nil
    }
}

private func elements(named name: String, in text: String) -> [String] {
    var result: [String] = []
    var index = text.startIndex
    let open = "<\(name)"
    let close = "</\(name)>"
    while let start = text.range(of: open, range: index..<text.endIndex) {
        guard let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
            break
        }
        result.append(String(text[start.lowerBound..<end.upperBound]))
        index = end.upperBound
    }
    return result
}

private func firstIntTag(_ name: String, in text: String) -> Int? {
    firstStringTag(name, in: text).flatMap(Int.init)
}

private func firstStringTag(_ name: String, in text: String) -> String? {
    let open = "<\(name)>"
    let close = "</\(name)>"
    guard let start = text.range(of: open),
          let end = text.range(of: close, range: start.upperBound..<text.endIndex) else {
        return nil
    }
    return String(text[start.upperBound..<end.lowerBound])
}

private func dotCount(in text: String) -> Int {
    text.components(separatedBy: "<dot").count - 1
}

private func impliedDivisions(type: String, dots: Int, divisions: Int) -> Int? {
    let baseAtFour: [String: Int] = [
        "whole": 16,
        "half": 8,
        "quarter": 4,
        "eighth": 2,
        "16th": 1,
    ]
    guard let base = baseAtFour[type] else { return nil }
    var value = base * divisions / 4
    var add = value / 2
    var remaining = dots
    while remaining > 0 {
        value += add
        add /= 2
        remaining -= 1
    }
    return value
}
