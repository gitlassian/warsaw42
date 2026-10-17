"""Parse the simple subset of OSM `opening_hours` that is safe to trust.

    parse("Mo-Fr 07:30-15:30; Sa,Su off")  ->  Parsed("scheduled", {mon..fri: [["07:30","15:30"]], sat: [], sun: []})

Supported: `24/7`, rules separated by `;`, weekday lists and ranges (Mo-Fr, Sa,Su), several time ranges per day,
`off`/`closed`, and rules without weekdays (every day). Later rules override earlier ones for the same days.
In this syntax a weekday that no rule mentions is closed, which is how the weekend becomes known.
Anything else (months, weeks, public holidays, sunrise/sunset, comments, intervals across midnight) returns None,
so the record keeps whatever the city data says.
"""
import re

from .hours import DAY_KEYS, OSM_DAYS, Parsed, empty_schedule, validate_schedule

_TIME = r"(?:[01]?\d|2[0-4]):[0-5]\d"
_RANGE = re.compile(rf"^({_TIME})-({_TIME})$")
_DAYS = re.compile(r"^(?:Mo|Tu|We|Th|Fr|Sa|Su)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?(?:,(?:Mo|Tu|We|Th|Fr|Sa|Su)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?)*$")


def _days(spec):
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        i = OSM_DAYS.index(a)
        j = OSM_DAYS.index(b) if b else i
        if j < i:  # "Sa-Mo" wraps over Sunday; refuse rather than guess
            return None
        out.extend(range(i, j + 1))
    return out


def _clock(t):
    h, m = t.split(":")
    return f"{int(h):02d}:{m}"


def parse(text):
    text = (text or "").strip()
    if not text:
        return None
    if text == "24/7":
        return Parsed("24/7", {d: [["00:00", "24:00"]] for d in DAY_KEYS}, source="osm", note="")
    sched = {d: [] for d in DAY_KEYS}
    for rule in (r.strip() for r in text.split(";")):
        if not rule:
            continue
        m = re.match(r"^(?:(?P<days>\S+)\s+)?(?P<times>.+)$", rule)
        days_spec, times = m["days"], m["times"].strip()
        if days_spec and not _DAYS.match(days_spec):  # a bare time range has no days part
            days_spec, times = None, rule
        days = _days(days_spec) if days_spec else list(range(7))
        if days is None:
            return None
        if times in ("off", "closed"):
            intervals = []
        else:
            intervals = []
            for piece in (p.strip() for p in times.split(",")):
                r = _RANGE.match(piece)
                if not r:
                    return None
                start, end = _clock(r[1]), _clock(r[2])
                if end <= start:  # across midnight: not supported
                    return None
                intervals.append([start, end])
        for i in days:
            sched[DAY_KEYS[i]] = [list(iv) for iv in intervals]
    if not validate_schedule(sched) or not any(sched[d] for d in DAY_KEYS):
        return None
    return Parsed("scheduled", sched, source="osm", note="")
