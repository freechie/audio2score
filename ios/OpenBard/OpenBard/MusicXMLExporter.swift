import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum MusicXMLExportError: Error, Equatable {
    case noScore
}

enum MusicXMLExporter {
    static let divisionsPerQuarter = 4 // gridBeats 0.25 → 1 division

    /// Build partwise MusicXML 3.1 from a ScoreBuilder score.
    static func makeData(from score: Score) throws -> Data {
        guard !score.measures.isEmpty else { throw MusicXMLExportError.noScore }

        let tieStops = tieStopKeys(in: score)
        var xml = ""
        xml += #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += #"<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">"# + "\n"
        xml += #"<score-partwise version="3.1">"# + "\n"
        xml += "  <work>\n"
        xml += "    <work-title>openBard</work-title>\n"
        xml += "  </work>\n"
        xml += "  <part-list>\n"
        xml += #"    <score-part id="P1">"# + "\n"
        xml += "      <part-name>Music</part-name>\n"
        xml += "    </score-part>\n"
        xml += "  </part-list>\n"
        xml += #"  <part id="P1">"# + "\n"

        for measure in score.measures {
            xml += emitMeasure(measure, score: score, tieStops: tieStops, isFirst: measure.index == 0)
        }

        xml += "  </part>\n"
        xml += "</score-partwise>\n"

        guard let data = xml.data(using: .utf8) else { throw MusicXMLExportError.noScore }
        return data
    }

    static func makeData(from notes: [NoteEvent], tempoBpm: Double? = nil) throws -> Data {
        guard let score = ScoreBuilder.build(from: notes, tempoBpm: tempoBpm) else {
            throw MusicXMLExportError.noScore
        }
        return try makeData(from: score)
    }

    // MARK: - Measure emission

    private struct ChordGroup {
        var startBeat: Double
        var durationBeats: Double
        var notes: [ScoreNote]
    }

    private static func emitMeasure(
        _ measure: ScoreMeasure,
        score: Score,
        tieStops: Set<String>,
        isFirst: Bool
    ) -> String {
        var xml = "    <measure number=\"\(measure.index + 1)\">\n"

        if isFirst {
            xml += "      <attributes>\n"
            xml += "        <divisions>\(divisionsPerQuarter)</divisions>\n"
            xml += "        <key>\n"
            xml += "          <fifths>0</fifths>\n"
            xml += "        </key>\n"
            xml += "        <time>\n"
            xml += "          <beats>4</beats>\n"
            xml += "          <beat-type>4</beat-type>\n"
            xml += "        </time>\n"
            xml += "        <clef>\n"
            switch score.clef {
            case .bass:
                xml += "          <sign>F</sign>\n"
                xml += "          <line>4</line>\n"
            case .treble, .unknown:
                xml += "          <sign>G</sign>\n"
                xml += "          <line>2</line>\n"
            }
            xml += "        </clef>\n"
            xml += "      </attributes>\n"
            xml += "      <direction placement=\"above\">\n"
            xml += "        <direction-type>\n"
            xml += "          <metronome>\n"
            xml += "            <beat-unit>quarter</beat-unit>\n"
            xml += "            <per-minute>\(Int(score.tempoBpm.rounded()))</per-minute>\n"
            xml += "          </metronome>\n"
            xml += "        </direction-type>\n"
            xml += "        <sound tempo=\"\(formatNumber(score.tempoBpm))\"/>\n"
            xml += "      </direction>\n"
        }

        let origin = Double(measure.index) * ScoreBuilder.beatsPerMeasure
        let voices = assignVoices(chordGroups(in: measure))
        if voices.isEmpty {
            xml += emitSpelledRest(durationBeats: ScoreBuilder.beatsPerMeasure, voice: 1)
        } else {
            let measureDivisions = Int(ScoreBuilder.beatsPerMeasure * Double(divisionsPerQuarter))
            for (voiceIndex, groups) in voices.enumerated() {
                if voiceIndex > 0 {
                    xml += emitBackup(divisions: measureDivisions)
                }
                xml += emitVoice(
                    groups,
                    origin: origin,
                    voice: voiceIndex + 1,
                    tieStops: tieStops
                )
            }
        }

        xml += "    </measure>\n"
        return xml
    }

    private static func chordGroups(in measure: ScoreMeasure) -> [ChordGroup] {
        let notes = measure.items.compactMap { item -> ScoreNote? in
            if case .note(let note) = item { return note }
            return nil
        }
        .sorted { lhs, rhs in
            if abs(lhs.startBeat - rhs.startBeat) > 1e-9 {
                return lhs.startBeat < rhs.startBeat
            }
            if abs(lhs.durationBeats - rhs.durationBeats) > 1e-9 {
                return lhs.durationBeats > rhs.durationBeats
            }
            return lhs.pitchMidi < rhs.pitchMidi
        }

        var groups: [ChordGroup] = []
        for note in notes {
            if var last = groups.last,
               abs(last.startBeat - note.startBeat) < 1e-9,
               abs(last.durationBeats - note.durationBeats) < 1e-9 {
                last.notes.append(note)
                groups[groups.count - 1] = last
            } else {
                groups.append(
                    ChordGroup(
                        startBeat: note.startBeat,
                        durationBeats: note.durationBeats,
                        notes: [note]
                    )
                )
            }
        }
        return groups
    }

    private static func assignVoices(_ groups: [ChordGroup]) -> [[ChordGroup]] {
        var voices: [[ChordGroup]] = []
        var ends: [Double] = []
        for group in groups {
            var assigned: Int?
            for index in 0..<ends.count {
                if group.startBeat >= ends[index] - 1e-9 {
                    assigned = index
                    break
                }
            }
            if let assigned {
                voices[assigned].append(group)
                ends[assigned] = group.startBeat + group.durationBeats
            } else {
                voices.append([group])
                ends.append(group.startBeat + group.durationBeats)
            }
        }
        return voices
    }

    private static func emitVoice(
        _ groups: [ChordGroup],
        origin: Double,
        voice: Int,
        tieStops: Set<String>
    ) -> String {
        var xml = ""
        var cursor = origin
        let barEnd = origin + ScoreBuilder.beatsPerMeasure
        for group in groups {
            if group.startBeat > cursor + 1e-9 {
                xml += emitSpelledRest(durationBeats: group.startBeat - cursor, voice: voice)
            }
            xml += emitSpelledChord(group, voice: voice, tieStops: tieStops)
            cursor = max(cursor, group.startBeat + group.durationBeats)
        }
        if barEnd > cursor + 1e-9 {
            xml += emitSpelledRest(durationBeats: barEnd - cursor, voice: voice)
        }
        return xml
    }

    private static func emitSpelledChord(
        _ group: ChordGroup,
        voice: Int,
        tieStops: Set<String>
    ) -> String {
        let pieces = DurationSpelling.pieces(forBeats: group.durationBeats)
        var xml = ""
        for (pieceIndex, piece) in pieces.enumerated() {
            let isFirstPiece = pieceIndex == 0
            let isLastPiece = pieceIndex == pieces.count - 1
            for (noteIndex, note) in group.notes.enumerated() {
                let stopKey = "\(note.pitchMidi)@\(formatBeat(note.startBeat))"
                let tieStop = (!isFirstPiece) || tieStops.contains(stopKey)
                let tieStart = (!isLastPiece) || note.tiedToNext
                xml += emitNote(
                    note,
                    isChord: noteIndex > 0,
                    voice: voice,
                    piece: piece,
                    tieStop: tieStop,
                    tieStart: tieStart
                )
            }
        }
        return xml
    }

    private static func emitNote(
        _ note: ScoreNote,
        isChord: Bool,
        voice: Int,
        piece: DurationSpelling.Piece,
        tieStop: Bool,
        tieStart: Bool
    ) -> String {
        let pitch = midiToPitch(note.pitchMidi)
        var xml = "      <note>\n"
        if isChord {
            xml += "        <chord/>\n"
        }
        xml += "        <pitch>\n"
        xml += "          <step>\(pitch.step)</step>\n"
        if let alter = pitch.alter {
            xml += "          <alter>\(alter)</alter>\n"
        }
        xml += "          <octave>\(pitch.octave)</octave>\n"
        xml += "        </pitch>\n"
        xml += "        <duration>\(piece.divisions)</duration>\n"
        if tieStop {
            xml += "        <tie type=\"stop\"/>\n"
        }
        if tieStart {
            xml += "        <tie type=\"start\"/>\n"
        }
        xml += "        <voice>\(voice)</voice>\n"
        xml += "        <type>\(piece.type)</type>\n"
        for _ in 0..<piece.dots {
            xml += "        <dot/>\n"
        }
        if tieStop || tieStart {
            xml += "        <notations>\n"
            if tieStop {
                xml += "          <tied type=\"stop\"/>\n"
            }
            if tieStart {
                xml += "          <tied type=\"start\"/>\n"
            }
            xml += "        </notations>\n"
        }
        xml += "      </note>\n"
        return xml
    }

    private static func emitSpelledRest(durationBeats: Double, voice: Int) -> String {
        DurationSpelling.pieces(forBeats: durationBeats).map { piece in
            emitRest(piece: piece, voice: voice)
        }.joined()
    }

    private static func emitRest(piece: DurationSpelling.Piece, voice: Int) -> String {
        var xml = "      <note>\n"
        xml += "        <rest/>\n"
        xml += "        <duration>\(piece.divisions)</duration>\n"
        xml += "        <voice>\(voice)</voice>\n"
        xml += "        <type>\(piece.type)</type>\n"
        for _ in 0..<piece.dots {
            xml += "        <dot/>\n"
        }
        xml += "      </note>\n"
        return xml
    }

    private static func emitBackup(divisions: Int) -> String {
        var xml = "      <backup>\n"
        xml += "        <duration>\(divisions)</duration>\n"
        xml += "      </backup>\n"
        return xml
    }

    private enum DurationSpelling {
        struct Piece: Equatable {
            var type: String
            var dots: Int
            var divisions: Int
        }

        private enum Glyph {
            case whole
            case half
            case quarter
            case eighth
            case sixteenth

            var typeName: String {
                switch self {
                case .whole:
                    return "whole"
                case .half:
                    return "half"
                case .quarter:
                    return "quarter"
                case .eighth:
                    return "eighth"
                case .sixteenth:
                    return "16th"
                }
            }

            var undottedDivisions: Int {
                switch self {
                case .whole:
                    return 16
                case .half:
                    return 8
                case .quarter:
                    return 4
                case .eighth:
                    return 2
                case .sixteenth:
                    return 1
                }
            }
        }

        private static let shapes: [[(glyph: Glyph, dots: Int)]] = [
            [],
            [(.sixteenth, 0)],
            [(.eighth, 0)],
            [(.eighth, 1)],
            [(.quarter, 0)],
            [(.quarter, 0), (.sixteenth, 0)],
            [(.quarter, 1)],
            [(.quarter, 1), (.sixteenth, 0)],
            [(.half, 0)],
            [(.half, 0), (.sixteenth, 0)],
            [(.half, 0), (.eighth, 0)],
            [(.half, 0), (.eighth, 1)],
            [(.half, 1)],
            [(.half, 1), (.sixteenth, 0)],
            [(.half, 1), (.eighth, 0)],
            [(.half, 1), (.eighth, 1)],
            [(.whole, 0)],
        ]

        static func pieces(forBeats beats: Double) -> [Piece] {
            let divisions = max(1, Int((beats * Double(divisionsPerQuarter)).rounded()))
            return pieces(divisions: min(divisions, 16))
        }

        static func pieces(divisions: Int) -> [Piece] {
            shapes[divisions].map { shape in
                Piece(
                    type: shape.glyph.typeName,
                    dots: shape.dots,
                    divisions: countedDivisions(glyph: shape.glyph, dots: shape.dots)
                )
            }
        }

        private static func countedDivisions(glyph: Glyph, dots: Int) -> Int {
            let base = glyph.undottedDivisions
            var value = base
            var add = base / 2
            var remaining = dots
            while remaining > 0 {
                value += add
                add /= 2
                remaining -= 1
            }
            return value
        }
    }

    // MARK: - Helpers

    private static func tieStopKeys(in score: Score) -> Set<String> {
        var keys = Set<String>()
        for measure in score.measures {
            for item in measure.items {
                if case .note(let note) = item, note.tiedToNext {
                    let end = note.startBeat + note.durationBeats
                    keys.insert("\(note.pitchMidi)@\(formatBeat(end))")
                }
            }
        }
        return keys
    }

    static func midiToPitch(_ midi: Int) -> (step: String, alter: Int?, octave: Int) {
        let names = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
        let alters: [Int?] = [nil, 1, nil, 1, nil, nil, 1, nil, 1, nil, 1, nil]
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return (names[pc], alters[pc], octave)
    }

    static func noteType(for durationBeats: Double) -> String {
        DurationSpelling.pieces(forBeats: durationBeats)[0].type
    }

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func formatBeat(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

struct MusicXMLFileDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .musicXML) { document in
            document.data
        }
    }
}

extension UTType {
    static var musicXML: UTType {
        UTType(filenameExtension: "musicxml")
            ?? UTType(filenameExtension: "xml")
            ?? .xml
    }
}
