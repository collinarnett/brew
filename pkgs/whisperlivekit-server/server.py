import asyncio
import json
import logging
import os
import sys
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from whisperlivekit import AudioProcessor, TranscriptionEngine, get_inline_ui_html, parse_args

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logging.getLogger().setLevel(logging.WARNING)
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Extract --output-dir before upstream parse_args() sees it
output_dir = None
_argv = sys.argv[:]
_i = 1
while _i < len(_argv):
    if _argv[_i] == "--output-dir" and _i + 1 < len(_argv):
        output_dir = _argv[_i + 1]
        del _argv[_i : _i + 2]
        break
    elif _argv[_i].startswith("--output-dir="):
        output_dir = _argv[_i].split("=", 1)[1]
        del _argv[_i]
        break
    _i += 1
sys.argv = _argv

config = parse_args()
transcription_engine = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global transcription_engine
    transcription_engine = TranscriptionEngine(config=config)
    yield


app = FastAPI(lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def get():
    return HTMLResponse(get_inline_ui_html())


async def handle_websocket_results(websocket, results_generator, transcript_file):
    """Consumes results from the audio processor and sends them via WebSocket."""
    last_response_dict = None
    try:
        async for response in results_generator:
            response_dict = response.to_dict()
            last_response_dict = response_dict
            await websocket.send_json(response_dict)

        # Write final state to JSONL at session end (lines are revised
        # throughout the session, so only the final snapshot is authoritative)
        if transcript_file is not None and last_response_dict is not None:
            ts = datetime.now(timezone.utc).isoformat()
            for line in last_response_dict.get("lines", []):
                if line.get("text"):
                    record = {
                        "ts": ts,
                        "start": line["start"],
                        "end": line["end"],
                        "speaker": line["speaker"],
                        "text": line["text"],
                    }
                    lang = line.get("detected_language")
                    if lang:
                        record["language"] = lang
                    transcript_file.write(json.dumps(record) + "\n")
            buf = last_response_dict.get("buffer_transcription", "").strip()
            if buf:
                transcript_file.write(json.dumps({"ts": ts, "text": buf, "buffer": True}) + "\n")
            transcript_file.flush()

        logger.info("Results generator finished. Sending 'ready_to_stop' to client.")
        await websocket.send_json({"type": "ready_to_stop"})
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected while handling results.")
    except Exception as e:
        logger.exception(f"Error in WebSocket results handler: {e}")


@app.websocket("/asr")
async def websocket_endpoint(websocket: WebSocket):
    global transcription_engine
    audio_processor = AudioProcessor(transcription_engine=transcription_engine)
    await websocket.accept()
    logger.info("WebSocket connection opened.")

    try:
        await websocket.send_json({"type": "config", "useAudioWorklet": bool(config.pcm_input)})
    except Exception as e:
        logger.warning(f"Failed to send config to client: {e}")

    transcript_file = None
    if output_dir is not None:
        os.makedirs(output_dir, exist_ok=True)
        session_id = uuid.uuid4().hex[:8]
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        filepath = os.path.join(output_dir, f"{timestamp}_{session_id}.jsonl")
        transcript_file = open(filepath, "a")
        logger.info(f"Transcript output: {filepath}")

    results_generator = await audio_processor.create_tasks()
    websocket_task = asyncio.create_task(
        handle_websocket_results(websocket, results_generator, transcript_file)
    )

    try:
        while True:
            message = await websocket.receive_bytes()
            await audio_processor.process_audio(message)
    except KeyError as e:
        if "bytes" in str(e):
            logger.warning("Client has closed the connection.")
        else:
            logger.error(f"Unexpected KeyError in websocket_endpoint: {e}", exc_info=True)
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected by client.")
    except Exception as e:
        logger.error(f"Unexpected error in websocket_endpoint: {e}", exc_info=True)
    finally:
        logger.info("Cleaning up WebSocket endpoint...")
        if not websocket_task.done():
            websocket_task.cancel()
        try:
            await websocket_task
        except asyncio.CancelledError:
            logger.info("WebSocket results handler task was cancelled.")
        except Exception as e:
            logger.warning(f"Exception while awaiting websocket_task: {e}")

        await audio_processor.cleanup()

        if transcript_file is not None:
            transcript_file.close()
            logger.info("Transcript file closed.")

        logger.info("WebSocket endpoint cleaned up.")


def main():
    import uvicorn

    uvicorn_kwargs = {
        "app": app,
        "host": config.host,
        "port": config.port,
        "reload": False,
        "log_level": "info",
        "lifespan": "on",
    }

    ssl_kwargs = {}
    if config.ssl_certfile or config.ssl_keyfile:
        if not (config.ssl_certfile and config.ssl_keyfile):
            raise ValueError("Both --ssl-certfile and --ssl-keyfile must be specified together.")
        ssl_kwargs = {
            "ssl_certfile": config.ssl_certfile,
            "ssl_keyfile": config.ssl_keyfile,
        }

    if ssl_kwargs:
        uvicorn_kwargs.update(ssl_kwargs)
    if config.forwarded_allow_ips:
        uvicorn_kwargs["forwarded_allow_ips"] = config.forwarded_allow_ips

    uvicorn.run(**uvicorn_kwargs)


if __name__ == "__main__":
    main()
