"""Voices the tutorial cards with a local Voicebox (http://127.0.0.1:17493).

Reads every _info / _step card (and the closing card) from tutorial_panel.gd,
speaks its text with the Voicebox profile PROFILE_NAME - its engine and its
own effects chain (the presets set up in Voicebox) - and saves one WAV per
card as sounds/tutorial/<slug>.wav, the slug made from the card title the way
tutorial_panel.gd makes it. Cards whose WAV already exists are skipped; pass
--force to redo them all, or card titles to redo just those.

    python tools/generate_tutorial_voice.py [--force] ["Card title" ...]
"""

import json
import re
import sys
import time
import urllib.request
from pathlib import Path

API = "http://127.0.0.1:17493"
PROFILE_NAME = "voice"
ROOT = Path(__file__).resolve().parent.parent
TUTORIAL = ROOT / "tutorial_panel.gd"
OUT_DIR = ROOT / "sounds" / "tutorial"
OUTRO_TITLE = "Tutorial complete"

# Key names as they should be read out.
SPOKEN = [
    (r"\bLMB\b", "left mouse button"),
    (r"\bRMB\b", "right mouse button"),
    (r"\bMMB\b", "middle mouse button"),
    (r"\bWASD\b", "W A S D"),
    (r"\bEsc\b", "Escape"),
    (r"\bHUD\b", "H U D"),
    (r"\bRCS\b", "R C S"),
    (r"Ctrl\+click", "control click"),
    (r"\bCtrl\b", "Control"),
    (r"\. \(period\)", "period"),
    (r"Settings > Gameplay", "Settings, Gameplay"),
    (r"4x", "four times"),
    (r" - ", ", "),
]


def slug(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")


def cards() -> list[tuple[str, str]]:
    source = TUTORIAL.read_text(encoding="utf-8")
    found = re.findall(r'_(?:info|step)\(\s*"[A-Z]+",\s*"([^"]+)",\s*"([^"]+)"', source)
    outro = re.search(r'if _outro_time >= 0\.0:\s*return "([^"]+)"', source)
    if outro:
        # "Click to close." is for the eye only.
        found.append((OUTRO_TITLE, outro.group(1).replace(" Click to close.", "")))
    return found


def spoken(text: str) -> str:
    for pattern, words in SPOKEN:
        text = re.sub(pattern, words, text)
    return text


def call(method: str, path: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=600) as response:
        raw = response.read()
        kind = response.headers.get("Content-Type", "")
    return json.loads(raw) if "json" in kind else raw


def generate(profile: dict, text: str) -> bytes:
    generation = call("POST", "/generate", {
        "profile_id": profile["id"],
        "text": text,
        "language": profile.get("language") or "en",
        "engine": profile.get("default_engine") or profile.get("preset_engine"),
        "effects_chain": profile.get("effects_chain"),
        "normalize": True,
    })
    while generation.get("status") not in ("completed", "failed", "error", "cancelled"):
        time.sleep(1.0)
        generation = call("GET", "/history/%s" % generation["id"])
    if generation.get("status") != "completed":
        raise RuntimeError(generation.get("error") or generation.get("status"))
    return call("GET", "/audio/%s" % generation["id"])


def main() -> None:
    args = sys.argv[1:]
    force = "--force" in args
    only = {slug(a) for a in args if a != "--force"}
    profiles = call("GET", "/profiles")
    profile = next((p for p in profiles if p["name"] == PROFILE_NAME), None)
    if profile is None:
        sys.exit("No Voicebox profile named %r" % PROFILE_NAME)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for title, text in cards():
        name = slug(title)
        target = OUT_DIR / (name + ".wav")
        if only and name not in only:
            continue
        if target.exists() and not force and not only:
            print("skip", name)
            continue
        print("voicing", name, "...", flush=True)
        target.write_bytes(generate(profile, spoken(text)))
    print("done")


if __name__ == "__main__":
    main()
