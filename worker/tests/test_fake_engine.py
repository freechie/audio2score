from fastapi.testclient import TestClient

from app.engines.fake import build_demo_transcription
from app.main import app

client = TestClient(app)


def test_fake_engine_returns_c_major_scale() -> None:
    result = build_demo_transcription()

    assert result.engine == "dsp_v0"
    assert result.key_guess == "C major"
    assert [note.pitch_midi for note in result.note_events] == [
        60,
        62,
        64,
        65,
        67,
        69,
        71,
        72,
    ]


def test_demo_endpoint_returns_note_events() -> None:
    response = client.get("/v1/transcriptions/demo")

    assert response.status_code == 200

    body = response.json()
    assert body["engine"] == "dsp_v0"
    assert body["tempo_bpm"] == 120
    assert len(body["note_events"]) == 8
    assert body["note_events"][0]["pitch_midi"] == 60
