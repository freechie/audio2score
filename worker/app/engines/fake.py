from app.models import NoteEvent, TranscriptionResult


def build_demo_transcription() -> TranscriptionResult:
    pitches = [60, 62, 64, 65, 67, 69, 71, 72]

    notes = [
        NoteEvent(
            pitch_midi=pitch,
            onset_seconds=index * 0.5,
            duration_seconds=0.5,
            velocity=0.8,
            confidence=1.0,
            staff_hint="treble",
        )
        for index, pitch in enumerate(pitches)
    ]
    return TranscriptionResult(
        engine="dsp_v0",
        engine_version="0.1.0",
        tempo_bpm=120,
        key_guess="C major",
        note_events=notes,
    )
