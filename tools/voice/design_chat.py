#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["sounddevice>=0.5", "numpy>=1.26", "requests>=2.31"]
# ///
"""A spoken back-and-forth about Assay's design, before anything gets built.

    make talk                      # or: tools/voice/design_chat.py
    tools/voice/design_chat.py --text        # type instead of speaking
    tools/voice/design_chat.py --topic "belt throughput"

How it works: press Enter to talk, Enter again to stop. Your words go to
ElevenLabs Scribe, the transcript goes to Claude Code (`claude -p`, so it
has the repo and your login, no API key needed), and the reply is spoken
with ElevenLabs. Claude is told to keep replies short and ask one question
at a time. Say "wrap it up" and it writes a design note to docs/design-notes/.

Needs: ELEVENLABS_API_KEY (env or ~/.zshrc), `claude` on PATH, `ffplay`
(brew install ffmpeg), a microphone.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import queue
import random
import re
import subprocess
import sys
import threading
import time
import uuid
import wave
from pathlib import Path

import requests

REPO = Path(__file__).resolve().parents[2]
NOTES_DIR = REPO / "docs" / "design-notes"
TRANSCRIPTS_DIR = NOTES_DIR / "transcripts"

DEFAULT_VOICE = "SAz9YHcvj6GT2YYXdXww"  # "River": relaxed, neutral
CUE_DIR = Path(__file__).resolve().parent / ".cues"  # cached clips, git-ignored

# Short clips played while Claude works, so silence never means "dead".
ACK_CUES = ["Mm-hm.", "Okay.", "Right.", "Hmm, let me think about that.", "Got it, one sec."]
WAIT_CUES = ["Hmm...", "Still thinking.", "Bear with me a moment.", "Okay, so..."]
WAIT_CUE_EVERY = 7.0  # seconds between "still here" cues
TTS_MODEL = "eleven_flash_v2_5"  # fastest; eleven_multilingual_v2 for quality
STT_MODEL = "scribe_v1"
SAMPLE_RATE = 16_000

SYSTEM_PROMPT = """\
You are having a spoken conversation with a founder of Assay (this repo) about
the game's design and direction. Your job is to understand what they want
well enough to write it down, not to build anything.

Rules for every reply:
- Speak, don't write: one to three short sentences of plain conversational
  English. No lists, headings, markdown, code, file paths, or symbols. Numbers
  and units as words where natural. Sound like a person thinking out loud:
  now and then open with a natural lead-in such as "Okay, so", "Hmm, right",
  or "Yeah, that makes sense", and vary it.
- Ask at most one question per reply, and only when it moves the design
  forward. Prefer sharp questions about trade-offs, edge cases, and what the
  player actually does, over vague ones.
- When you think you understand a point, restate it in one sentence so the
  founder can correct you.
- Push back briefly when something conflicts with earlier decisions in
  CLAUDE.md or GAME.md, or with the sim/renderer separation, then defer to
  the founder.
- Do not edit or create files during the conversation, and do not start
  building. Reading repo files to check facts is fine.

When the founder says something like "wrap it up", "write it up", or "we're
done": write a design note to {notes_dir}/{date}-<short-slug>.md with these
sections: Summary (three sentences), Decisions (numbered, each one
testable), Open questions, Suggested next steps (ordered, small). Then say
out loud, in two sentences, that it's written and what the first next step
is. Only then may you touch files.
"""

GREETING_PROMPT = (
    "Start the conversation. Greet the founder in one sentence and ask what "
    "part of the game they want to think through today."
)


def die(msg: str) -> None:
    print(f"\n{msg}", file=sys.stderr)
    sys.exit(1)


def elevenlabs_key() -> str:
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        try:
            key = subprocess.run(
                ["zsh", "-ic", "echo $ELEVENLABS_API_KEY"],
                capture_output=True, text=True, timeout=10,
            ).stdout.strip().splitlines()[-1]
        except Exception:
            key = ""
    if not key:
        die("ELEVENLABS_API_KEY is not set. Export it or add it to ~/.zshrc.")
    return key


# ------------------------------------------------------------------ audio in

def record_until_enter() -> bytes | None:
    """Record 16 kHz mono int16 from the default mic until Enter. WAV bytes."""
    import numpy as np
    import sounddevice as sd

    chunks: queue.Queue = queue.Queue()

    def on_audio(indata, frames, t, status):
        chunks.put(indata.copy())

    try:
        stream = sd.InputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="int16", callback=on_audio
        )
        stream.start()
    except Exception as e:  # no mic, no permission, ...
        print(f"Microphone problem: {e}. Use --text to type instead.")
        return None

    started = time.time()
    input("  recording... press Enter when you're done ")
    stream.stop()
    stream.close()
    seconds = time.time() - started
    if seconds < 0.4:
        print("  (too short, ignored)")
        return None

    frames = []
    while not chunks.empty():
        frames.append(chunks.get())
    audio = np.concatenate(frames) if frames else np.zeros((0, 1), dtype="int16")

    import io

    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(audio.tobytes())
    return buf.getvalue()


def transcribe(key: str, wav: bytes) -> str:
    r = requests.post(
        "https://api.elevenlabs.io/v1/speech-to-text",
        headers={"xi-api-key": key},
        data={"model_id": STT_MODEL, "language_code": "en"},
        files={"file": ("speech.wav", wav, "audio/wav")},
        timeout=120,
    )
    if r.status_code != 200:
        print(f"  transcription failed ({r.status_code}): {r.text[:200]}")
        return ""
    return r.json().get("text", "").strip()


# ----------------------------------------------------------------- audio out

class Speaker:
    """Streams ElevenLabs audio into ffplay. `stop()` cuts it off (barge-in)."""

    def __init__(self, key: str, voice: str, enabled: bool):
        self.key, self.voice, self.enabled = key, voice, enabled
        self.proc: subprocess.Popen | None = None
        self.thread: threading.Thread | None = None

    def say(self, text: str) -> None:
        if not self.enabled or not text.strip():
            return
        self.stop()
        self.proc = subprocess.Popen(
            ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-i", "pipe:0"],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        proc = self.proc

        def pump():
            try:
                with requests.post(
                    f"https://api.elevenlabs.io/v1/text-to-speech/{self.voice}/stream"
                    "?output_format=mp3_44100_128",
                    headers={"xi-api-key": self.key, "Content-Type": "application/json"},
                    json={"text": text, "model_id": TTS_MODEL},
                    stream=True, timeout=120,
                ) as r:
                    if r.status_code != 200:
                        print(f"\n  speech failed ({r.status_code}): {r.text[:200]}")
                        return
                    for chunk in r.iter_content(chunk_size=4096):
                        if proc.poll() is not None:
                            return
                        proc.stdin.write(chunk)
                        proc.stdin.flush()
            except (BrokenPipeError, OSError):
                pass
            finally:
                try:
                    proc.stdin.close()
                except OSError:
                    pass

        self.thread = threading.Thread(target=pump, daemon=True)
        self.thread.start()

    def play_file(self, path: Path) -> None:
        """Play a cached clip (non-blocking)."""
        if not self.enabled:
            return
        self.stop()
        self.proc = subprocess.Popen(
            ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", str(path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def cue(self, phrases: list[str]) -> None:
        clip = self.cue_clip(random.choice(phrases))
        if clip:
            self.play_file(clip)

    def cue_clip(self, phrase: str) -> Path | None:
        """The cached mp3 for a cue phrase, generating it on first use."""
        if not self.enabled:
            return None
        safe = re.sub(r"[^a-z0-9]+", "-", phrase.lower()).strip("-")
        path = CUE_DIR / self.voice / f"{safe}.mp3"
        if path.exists():
            return path
        path.parent.mkdir(parents=True, exist_ok=True)
        r = requests.post(
            f"https://api.elevenlabs.io/v1/text-to-speech/{self.voice}?output_format=mp3_44100_128",
            headers={"xi-api-key": self.key, "Content-Type": "application/json"},
            json={"text": phrase, "model_id": TTS_MODEL},
            timeout=60,
        )
        if r.status_code != 200:
            return None
        path.write_bytes(r.content)
        return path

    def warm_cues(self) -> None:
        for phrase in ACK_CUES + WAIT_CUES:
            self.cue_clip(phrase)

    def wait(self) -> None:
        if self.thread:
            self.thread.join()
        if self.proc:
            self.proc.wait()

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
        self.proc = None


# --------------------------------------------------------------------- brain

class ClaudeCode:
    """One Claude Code session (`claude -p --resume`) per conversation."""

    def __init__(self, model: str | None):
        self.session = str(uuid.uuid4())
        self.model = model
        self.first = True

    def ask(self, text: str) -> str:
        cmd = ["claude", "-p", "--output-format", "json",
               "--allowedTools", "Read", "Glob", "Grep", "Write", "Edit"]
        if self.first:
            today = dt.date.today().isoformat()
            system = SYSTEM_PROMPT.format(notes_dir=NOTES_DIR, date=today)
            cmd += ["--session-id", self.session, "--append-system-prompt", system]
            if self.model:
                cmd += ["--model", self.model]
        else:
            cmd += ["--resume", self.session]
        cmd.append(text)
        try:
            # stdin must be closed: `claude -p` would otherwise read our
            # terminal (or a pipe) as extra prompt text.
            out = subprocess.run(
                cmd, cwd=REPO, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=600
            )
        except FileNotFoundError:
            die("`claude` is not on PATH. Install Claude Code first.")
        self.first = False
        if out.returncode != 0:
            return f"Claude Code failed: {out.stderr.strip()[:300] or out.stdout.strip()[:300]}"
        try:
            reply = json.loads(out.stdout).get("result", "")
        except json.JSONDecodeError:
            reply = out.stdout
        return reply.strip()


def for_speech(text: str) -> str:
    """Strip anything a voice shouldn't read (paths, markdown, code)."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"[`*_#>]+", "", text)
    text = re.sub(r"\S+/\S+\.md", "the design note", text)
    return re.sub(r"\s+", " ", text).strip()


# ---------------------------------------------------------------------- main

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--text", action="store_true", help="type instead of using the microphone")
    ap.add_argument("--mute", action="store_true", help="don't speak replies, just print them")
    ap.add_argument("--voice", default=os.environ.get("ELEVENLABS_VOICE_ID", DEFAULT_VOICE))
    ap.add_argument("--model", default=None, help="Claude Code model (default: your session default)")
    ap.add_argument("--topic", default=None, help="what to talk about; skips the opening question")
    args = ap.parse_args()

    key = elevenlabs_key() if not (args.text and args.mute) else ""
    if not args.mute and subprocess.run(["which", "ffplay"], capture_output=True).returncode != 0:
        die("ffplay not found. Install it with: brew install ffmpeg")

    TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M")
    transcript_path = TRANSCRIPTS_DIR / f"{stamp}.md"
    transcript = [f"# Design chat, {stamp}\n"]

    def log(who: str, what: str) -> None:
        transcript.append(f"**{who}:** {what}\n")
        transcript_path.write_text("\n".join(transcript))

    brain = ClaudeCode(args.model)
    speaker = Speaker(key, args.voice, enabled=not args.mute)
    if speaker.enabled:
        print("  (preparing voice cues...)", end="", flush=True)
        speaker.warm_cues()
        print(" ready")

    def with_cues(work, label: str, ack: bool = True):
        """Run `work()` in the background; play cues and a spinner meanwhile."""
        result: dict = {}

        def run():
            result["value"] = work()

        t = threading.Thread(target=run, daemon=True)
        t.start()
        if ack:
            speaker.cue(ACK_CUES)
        started = last_cue = time.time()
        spinner = "|/-\\"
        tty = sys.stdout.isatty()
        i = 0
        while t.is_alive():
            t.join(0.15)
            i += 1
            if tty:
                print(f"\r  {label} {spinner[i % 4]} ", end="", flush=True)
            now = time.time()
            if now - last_cue > WAIT_CUE_EVERY and now - started > 3:
                speaker.cue(WAIT_CUES)
                last_cue = now
        if tty:
            print("\r" + " " * (len(label) + 6) + "\r", end="", flush=True)
        speaker.stop()
        return result.get("value")

    print("Assay design chat. Enter to talk, type to send text, 'q' to quit.")
    print("Say \"wrap it up\" when you're done and Claude writes the design note.\n")

    opener = GREETING_PROMPT if not args.topic else f"The founder wants to talk about: {args.topic}. Open with one sharp question about it."
    reply = with_cues(lambda: brain.ask(opener), "thinking", ack=False)
    print(f"Claude: {reply}\n")
    log("Claude", reply)
    speaker.say(for_speech(reply))

    try:
        while True:
            typed = input("> ").strip()
            speaker.stop()  # barge-in: anything you do cuts Claude off
            if typed.lower() in {"q", "quit", "exit"}:
                break
            spoke = False
            if typed:
                said = typed
            elif args.text:
                continue
            else:
                wav = record_until_enter()
                if not wav:
                    continue
                spoke = True
                said = with_cues(lambda: transcribe(key, wav), "listening")
                if not said:
                    print("  (heard nothing)")
                    continue
                print(f"You: {said}")
            log("You", said)
            # Spoken turns already got an acknowledgement while transcribing.
            reply = with_cues(lambda: brain.ask(said), "thinking", ack=not spoke)
            print(f"\nClaude: {reply}\n")
            log("Claude", reply)
            speaker.say(for_speech(reply))
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        speaker.stop()
        print(f"\nTranscript: {transcript_path}")


if __name__ == "__main__":
    main()
