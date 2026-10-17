"""LLM fallback for opening-hours strings the regex parser refuses.

Only the hours string is sent to the API (no names, addresses or coordinates).
Results are cached by exact string, so a periodic refresh only pays for new strings.

Env:
    OPENAI_API_KEY    required for live calls
    OPENAI_MODEL      default gpt-4o-mini
    OPENAI_BASE_URL   default https://api.openai.com/v1 (any OpenAI-compatible endpoint works)
"""
import json
import os
import time
import urllib.request
from datetime import datetime, timezone

from .hours import DAY_KEYS, Parsed, validate_schedule, empty_schedule

CACHE_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "data", "cache", "hours_cache.json")

SYSTEM = """You convert Polish opening-hours descriptions of public defibrillators (AED) into a weekly schedule.
Rules:
- Times are 24h local time. "24:00" is allowed as an end. If an interval crosses midnight, split it over two days.
- "dni robocze/powszednie" = Monday-Friday. Ignore public-holiday remarks, but mention them in "note".
- If the text says the device is available only during the opening hours of some institution ("w godzinach pracy ...")
  without giving the hours, or hours depend on season, school term or "selected" days, return status "unknown".
- If the text means always available (całodobowo), return status "24/7" and an empty schedule.
- Never guess hours that are not in the text. When unsure, return "unknown".
Return only JSON matching the schema."""

_DAY_SCHEMA = {
    "type": "array",
    "items": {
        "type": "object",
        "properties": {"start": {"type": "string"}, "end": {"type": "string"}},
        "required": ["start", "end"],
        "additionalProperties": False,
    },
}
SCHEMA = {
    "name": "aed_hours",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "status": {"type": "string", "enum": ["scheduled", "24/7", "unknown"]},
            "schedule": {
                "type": "object",
                "properties": {d: _DAY_SCHEMA for d in DAY_KEYS},
                "required": DAY_KEYS,
                "additionalProperties": False,
            },
            "note": {"type": "string"},
        },
        "required": ["status", "schedule", "note"],
        "additionalProperties": False,
    },
}


def load_cache(path=CACHE_PATH):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_cache(cache, path=CACHE_PATH):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cache, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, path)


def _call(text, model, base_url, key, tries=3):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": text}],
        "response_format": {"type": "json_schema", "json_schema": SCHEMA},
    }).encode()
    err = None
    for i in range(tries):
        try:
            req = urllib.request.Request(
                base_url.rstrip("/") + "/chat/completions", data=body, method="POST",
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(json.loads(r.read())["choices"][0]["message"]["content"])
        except Exception as e:  # network, 429, bad JSON: retry with backoff
            err = e
            time.sleep(2 * (i + 1))
    raise RuntimeError(f"LLM call failed: {err!r}")


def _to_parsed(out, model):
    sched = empty_schedule()
    for d in DAY_KEYS:
        sched[d] = [[iv["start"], iv["end"]] for iv in out["schedule"][d]]
    status = out["status"]
    if status == "24/7":
        return Parsed("24/7", {d: [["00:00", "24:00"]] for d in DAY_KEYS}, source=f"llm:{model}", note=out["note"])
    if status == "scheduled" and validate_schedule(sched) and any(sched[d] for d in DAY_KEYS):
        return Parsed("scheduled", sched, source=f"llm:{model}", note=out["note"])
    # invalid or empty answer: never trust it, keep the record as unknown
    return Parsed("unknown", empty_schedule(), source=f"llm:{model}", note=out.get("note", "") or "llm_invalid")


def resolve(text, cache, enabled=True):
    """Return Parsed for `text` using the cache; call the API only if allowed and needed."""
    key = (text or "").strip()
    if key in cache:
        c = cache[key]
        return Parsed(c["status"], c["schedule"], source=c["source"], note=c.get("note", ""))
    api_key = os.environ.get("OPENAI_API_KEY")
    if not enabled or not api_key:
        return Parsed("unknown", empty_schedule(), source="unparsed", note="needs_llm")
    model = os.environ.get("OPENAI_MODEL", "gpt-4o-mini")
    base = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
    try:
        p = _to_parsed(_call(key, model, base, api_key), model)
    except RuntimeError as e:  # one bad call must not break the whole build; not cached, retried next run
        return Parsed("unknown", empty_schedule(), source="llm_error", note=str(e)[:120])
    cache[key] = {"status": p.status, "schedule": p.schedule, "source": p.source, "note": p.note,
                  "ts": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    return p
