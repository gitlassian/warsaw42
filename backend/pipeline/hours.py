"""Parse free-text AED opening hours (Polish) into a weekly schedule.

Public API:
    parse_regex(text)   -> Parsed | None   (None means "send to the LLM fallback")
    validate_schedule() -> bool
    to_osm(schedule)    -> str             (OSM opening_hours syntax, for display / cross-checks)

Schedule format: {"mon": [["08:00", "16:00"]], ..., "sun": []}; "24:00" is allowed as an end.
Intervals that cross midnight are split across the two days.
"""
import re
from dataclasses import dataclass, field

DAY_KEYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
OSM_DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

# The metro entries only say "during station opening hours". Assumption, shown as such in the output.
METRO_HOURS = (5 * 60, 24 * 60)  # approx. 05:00-24:00 every day; the real timetable has a short night break

_DAYTOK = (
    r"(?:poniedzia[łl]\w*|pon\w*|pn|wtor\w*|wt|[śs]rod\w*|[śs]r|czwart\w*|czw|"
    r"pi[ąa]t\w*|pt|sobot\w*|sob|sb|niedziel\w*|niedz|ndz|nd)\.?"
)
_DAY_ITEM = re.compile(rf"(?<!\w)({_DAYTOK})(?:\s*(?:-|do)\s*({_DAYTOK}))?(?!\w)")
_DAY_INDEX = [
    (0, re.compile(r"^(?:poniedzia|pon|pn)")),
    (1, re.compile(r"^(?:wtor|wt)")),
    (2, re.compile(r"^(?:[śs]rod|[śs]r)")),
    (3, re.compile(r"^(?:czwart|czw)")),
    (4, re.compile(r"^(?:pi[ąa]t|pt)")),
    (5, re.compile(r"^(?:sobot|sob|sb)")),
    (6, re.compile(r"^(?:niedziel|niedz|ndz|nd)")),
]

_KW_WEEKDAYS = re.compile(r"(?:w\s+)?dni\s+(?:powszednie|robocze)|dzie[ńn]\s+powszedni")
_KW_WEEKEND = re.compile(r"weekend\w*")
_KW_DAILY = re.compile(
    r"codziennie|(?:przez\s+)?ca[łl]y\s+tydzie[ńn]|\b7\s*dni(?:\s+w\s+tygodniu)?|ka[żz]dego\s+dnia"
)

_T = r"(\d{1,2})(?:[:.;,](\d{2}))?"
_TIME_RE = re.compile(rf"(?:od\s+)?{_T}\s*(?:-|do)\s*{_T}(?!\d)")

_ALWAYS = re.compile(r"ca[łl]odob|24\s*h\b|24/7|non-?stop|ca[łl][ąa]\s+dob")
_METRO = re.compile(r"\bmetra\b|stacji\s+metra")
# anything that changes the meaning of a plain interval goes to the LLM
_HARD = re.compile(
    r"z\s+wy[łl][ąa]czeniem|opr[óo]cz|poza\b|z\s+wyj[ąa]tkiem|wyj[ąa]tk|przerw|[śs]wi[ąa]t|[śs]wi[ęe]t|dni\s+wolnych|dni\s+wolne|"
    r"niedost[ęe]pn|wakac|ferie|szkoln|semestr|okres|wybran|pierwsz|druga|drugi|trzeci|czwarta|ostatni|co\s+drug|"
    r"sezon|miesi[ąa]c|stycz|lutego|marc|kwiet|maj\b|czerw|lipc|sierp|wrze[śs]|pa[źz]dz|listop|grud|"
    r"nieczynn|zamkni|po\s+wcze[śs]niejszym|telefon|ochron|dzwon|kontakt|klucz|recepcj|portier"
)


@dataclass
class Parsed:
    status: str  # "24/7" | "scheduled" | "unknown"
    schedule: dict = field(default_factory=dict)
    assumed: list = field(default_factory=list)  # e.g. ["weekdays_assumed", "metro_hours_assumed"]
    source: str = "regex"
    note: str = ""


def empty_schedule():
    return {d: [] for d in DAY_KEYS}


def full_schedule():
    return {d: [["00:00", "24:00"]] for d in DAY_KEYS}


def normalize(text):
    t = (text or "").lower().strip()
    t = t.replace("–", "-").replace("—", "-").replace("−", "-").replace(" ", " ")
    return re.sub(r"\s+", " ", t)


def _day_index(tok):
    tok = tok.strip(". ")
    for i, rx in _DAY_INDEX:
        if rx.match(tok):
            return i
    return None


def _range(a, b):
    if a <= b:
        return list(range(a, b + 1))
    return list(range(a, 7)) + list(range(0, b + 1))  # wrap, e.g. "pt-pon"


def _days_in(ctx):
    """Days named in a context string; also returns the context with day words removed."""
    days = set()
    rest = ctx
    for kw, rng in ((_KW_DAILY, range(7)), (_KW_WEEKDAYS, range(5)), (_KW_WEEKEND, (5, 6))):
        if kw.search(rest):
            days.update(rng)
            rest = kw.sub(" ", rest)
    def _item(m):
        a = _day_index(m.group(1))
        b = _day_index(m.group(2)) if m.group(2) else None
        if a is None:
            return m.group(0)
        days.update(_range(a, b) if b is not None else [a])
        return " "
    rest = _DAY_ITEM.sub(_item, rest)
    return days, rest


def _minutes(h, m):
    h, m = int(h), int(m or 0)
    if h > 24 or m > 59 or (h == 24 and m):
        return None
    return h * 60 + m


def _fmt(mins):
    return f"{mins // 60:02d}:{mins % 60:02d}"


def _add(sched, days, start, end):
    """Add one interval to the given days; split if it crosses midnight."""
    if start == end:
        return False
    for d in days:
        if end > start:
            sched[DAY_KEYS[d]].append([_fmt(start), _fmt(end)])
        else:
            sched[DAY_KEYS[d]].append([_fmt(start), "24:00"])
            sched[DAY_KEYS[(d + 1) % 7]].append(["00:00", _fmt(end)])
    return True


def _merge(sched):
    for d in DAY_KEYS:
        iv = sorted((a, b) for a, b in sched[d])
        out = []
        for a, b in iv:
            if out and a <= out[-1][1]:
                out[-1][1] = max(out[-1][1], b)
            else:
                out.append([a, b])
        sched[d] = out
    return sched


def validate_schedule(s):
    """Structural sanity check used for both regex and LLM output."""
    if not isinstance(s, dict) or set(s) != set(DAY_KEYS):
        return False
    for d in DAY_KEYS:
        last = -1
        for iv in s[d]:
            if not (isinstance(iv, (list, tuple)) and len(iv) == 2):
                return False
            try:
                a = _minutes(*iv[0].split(":"))
                b = _minutes(*iv[1].split(":"))
            except Exception:
                return False
            if a is None or b is None or b <= a or a < last:
                return False
            last = b
    return True


def parse_regex(text):
    t = normalize(text)
    if not t:
        return None
    times = list(_TIME_RE.finditer(t))
    if not times:
        if _METRO.search(t) and not _HARD.search(t):
            sched = empty_schedule()
            for d in range(7):
                _add(sched, [d], *METRO_HOURS)
            return Parsed("scheduled", _merge(sched), ["metro_hours_assumed"])
        if _ALWAYS.search(t) and not _HARD.search(t.replace("24h", "").replace("24/7", "")):
            return Parsed("24/7", full_schedule())
        return None
    if _HARD.search(t) or _ALWAYS.search(t):
        return None

    # pair each time range with the day words that precede it (or follow it, for a single range)
    ctxs, leftover_parts, prev_end = [], [], 0
    for m in times:
        ctxs.append(t[prev_end:m.start()])
        prev_end = m.end()
    tail = t[prev_end:]
    day_sets = []
    for c in ctxs:
        days, rest = _days_in(c)
        day_sets.append(days)
        leftover_parts.append(rest)
    tail_days, tail_rest = _days_in(tail)
    leftover_parts.append(tail_rest)

    assumed = []
    if all(day_sets) is False or not any(day_sets):
        if len(times) == 1 and tail_days:
            day_sets = [tail_days]
        elif not any(day_sets) and not tail_days:
            day_sets = [set(range(5)) for _ in times]
            assumed.append("weekdays_assumed")
        else:
            return None
    elif not all(day_sets):
        return None

    if re.search(r"\d", " ".join(leftover_parts)):
        return None

    seen = set()
    for days in day_sets:
        if seen & days:
            return None  # same day described twice with different hours: let the LLM decide
        seen |= days
    sched = empty_schedule()
    for m, days in zip(times, day_sets):
        a, b = _minutes(m.group(1), m.group(2)), _minutes(m.group(3), m.group(4))
        if a is None or b is None or not _add(sched, sorted(days), a, b):
            return None
    sched = _merge(sched)
    if not validate_schedule(sched):
        return None
    return Parsed("scheduled", sched, assumed)


def to_osm(sched):
    """Compact OSM opening_hours string, e.g. 'Mo-Fr 08:00-16:00; Sa 10:00-14:00'."""
    groups, i = [], 0
    while i < 7:
        key = tuple(map(tuple, sched[DAY_KEYS[i]]))
        j = i
        while j + 1 < 7 and tuple(map(tuple, sched[DAY_KEYS[j + 1]])) == key:
            j += 1
        if key:
            days = OSM_DAYS[i] if i == j else f"{OSM_DAYS[i]}-{OSM_DAYS[j]}"
            groups.append(f"{days} " + ",".join(f"{a}-{b}" for a, b in key))
        i = j + 1
    if all(sched[d] == [["00:00", "24:00"]] for d in DAY_KEYS):
        return "24/7"
    return "; ".join(groups) if groups else "off"


def is_open(sched, dow, minute):
    """dow 0=Mon..6=Sun, minute 0..1439."""
    for a, b in sched[DAY_KEYS[dow]]:
        if _minutes(*a.split(":")) <= minute < _minutes(*b.split(":")):
            return True
    return False
