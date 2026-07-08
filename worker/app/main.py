from fastapi import FastAPI

from app.engines.fake import build_demo_transcription
from app.models import TranscriptionResult

app = FastAPI(title="Audio2Score Worker")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/transcriptions/demo", response_model=TranscriptionResult)
def demo_transcription() -> TranscriptionResult:
    return build_demo_transcription()
