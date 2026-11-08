"""ACE-Step 1.5 launcher + thin REST client."""

from __future__ import annotations

import json
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from game_utils_audio.paths import ACESTEP_DIR, BGM_OUTPUT_DIR, VENDORS_DIR, ensure_output_dirs
from game_utils_audio.wavutil import write_meta

ACESTEP_REPO = "https://github.com/ACE-Step/ACE-Step-1.5.git"
DEFAULT_UI = "http://127.0.0.1:7860"
DEFAULT_API = "http://127.0.0.1:8001"


def uv_available() -> bool:
    return shutil.which("uv") is not None


def git_available() -> bool:
    return shutil.which("git") is not None


def is_installed() -> bool:
    return (ACESTEP_DIR / "pyproject.toml").exists() or (ACESTEP_DIR / "README.md").exists()


def setup(force: bool = False) -> Path:
    if not git_available():
        raise RuntimeError("git is required to clone ACE-Step")
    if not uv_available():
        raise RuntimeError("uv is required. Install: https://docs.astral.sh/uv/")

    VENDORS_DIR.mkdir(parents=True, exist_ok=True)
    if is_installed() and not force:
        print(f"ACE-Step already present: {ACESTEP_DIR}")
    else:
        if ACESTEP_DIR.exists() and force:
            shutil.rmtree(ACESTEP_DIR)
        print(f"Cloning {ACESTEP_REPO} ...")
        subprocess.run(["git", "clone", "--depth", "1", ACESTEP_REPO, str(ACESTEP_DIR)], check=True)

    print("Running uv sync (first time may download a lot) ...")
    subprocess.run(["uv", "sync"], cwd=ACESTEP_DIR, check=True)
    print("ACE-Step setup done.")
    return ACESTEP_DIR


def _require_installed() -> None:
    if not is_installed():
        raise RuntimeError("ACE-Step not installed. Run: gu-audio bgm setup")


def start_ui() -> None:
    _require_installed()
    print(f"Starting ACE-Step Gradio UI → {DEFAULT_UI}")
    subprocess.run(["uv", "run", "acestep"], cwd=ACESTEP_DIR, check=False)


def start_api() -> None:
    _require_installed()
    print(f"Starting ACE-Step REST API → {DEFAULT_API}")
    subprocess.run(["uv", "run", "acestep-api"], cwd=ACESTEP_DIR, check=False)


def _http_json(method: str, url: str, body: dict[str, Any] | None = None, timeout: float = 30.0) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else {}


def api_healthy(base: str = DEFAULT_API) -> bool:
    for path in ("/health", "/"):
        try:
            urllib.request.urlopen(base.rstrip("/") + path, timeout=2)
            return True
        except Exception:
            continue
    # Some builds only expose task endpoints; treat connection refused as down,
    # but open TCP without 404-only as unknown — probe release_task shape via OPTIONS/GET models if any.
    try:
        urllib.request.urlopen(base.rstrip("/") + "/list_models", timeout=2)
        return True
    except urllib.error.HTTPError:
        return True
    except Exception:
        return False


def status() -> dict[str, Any]:
    return {
        "installed": is_installed(),
        "path": str(ACESTEP_DIR) if is_installed() else None,
        "uv": uv_available(),
        "git": git_available(),
        "api_up": api_healthy(),
        "api_url": DEFAULT_API,
        "ui_url": DEFAULT_UI,
    }


def generate(
    prompt: str,
    *,
    out: Path | None = None,
    base: str = DEFAULT_API,
    timeout_s: float = 600.0,
    duration: float | None = None,
) -> Path:
    """Submit a generation task to a running ACE-Step API and download the first audio result."""
    ensure_output_dirs()
    if not api_healthy(base):
        raise RuntimeError(
            f"ACE-Step API not reachable at {base}. Start it with: gu-audio bgm api"
        )

    payload: dict[str, Any] = {"prompt": prompt}
    if duration is not None:
        payload["duration"] = duration

    create = _http_json("POST", base.rstrip("/") + "/release_task", payload, timeout=60.0)
    data = create.get("data") or create
    task_id = data.get("task_id") or data.get("id")
    if not task_id:
        raise RuntimeError(f"Unexpected release_task response: {create}")

    deadline = time.time() + timeout_s
    result: dict[str, Any] | None = None
    while time.time() < deadline:
        query = _http_json(
            "POST",
            base.rstrip("/") + "/query_result",
            {"task_ids": [task_id]},
            timeout=60.0,
        )
        qdata = query.get("data") or query
        # API may return list or dict keyed by task id
        item: Any
        if isinstance(qdata, list) and qdata:
            item = qdata[0]
        elif isinstance(qdata, dict):
            item = qdata.get(task_id) or qdata.get("results", [qdata])[0] if qdata else {}
            if isinstance(item, list):
                item = item[0] if item else {}
        else:
            item = {}

        status_code = item.get("status")
        if status_code == 1:
            result = item
            break
        if status_code == 2:
            raise RuntimeError(f"ACE-Step generation failed: {item}")
        time.sleep(2.0)

    if result is None:
        raise TimeoutError(f"Timed out waiting for task {task_id}")

    audio_path = None
    for key in ("audio_path", "path", "file", "url"):
        if result.get(key):
            audio_path = result[key]
            break
    files = result.get("files") or result.get("audios") or []
    if not audio_path and files:
        audio_path = files[0] if isinstance(files[0], str) else files[0].get("path") or files[0].get("url")

    if not audio_path:
        raise RuntimeError(f"No audio path in result: {result}")

    # Remote download via /v1/audio?path=...
    if isinstance(audio_path, str) and not audio_path.startswith("http"):
        download_url = f"{base.rstrip('/')}/v1/audio?path={urllib.parse.quote(audio_path)}"
    else:
        download_url = str(audio_path)

    out = out or (BGM_OUTPUT_DIR / f"bgm_{task_id}.wav")
    out.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(download_url, timeout=120.0) as resp:
        out.write_bytes(resp.read())

    write_meta(
        out,
        {
            "kind": "bgm",
            "backend": "acestep-1.5",
            "prompt": prompt,
            "task_id": task_id,
            "api": base,
            "upstream": ACESTEP_REPO,
            "raw_result_keys": sorted(result.keys()),
        },
    )
    return out
