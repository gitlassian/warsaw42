"""Extract the floor an AED is on from its Polish location description.

Convention: 0 = ground floor (parter), 1 = first floor above ground ("I piętro"), -1 = basement.
Returns None when the text does not say, or says several different floors (never guess).
"""
import re



def _roman(r):
    r = r.lower()
    vals = {"i": 1, "v": 5, "x": 10, "l": 50}
    out = 0
    for a, b in zip(r, r[1:] + " "):
        out += -vals[a] if b in vals and vals[b] > vals[a] else vals[a]
    return out

_ORD = {"pierwsz": 1, "drug": 2, "trzeci": 3, "czwart": 4, "pi[ąa]t": 5, "sz[óo]st": 6}

_HALF = re.compile(r"p[óo][łl]pi[ęe]tr")  # mezzanine: neither floor
_GROUND = re.compile(r"parter|przyziemi|poziom\w*\s*[\"„”“]?\s*(?:0|o|zero)[\"„”“]?(?!\w)|\bpoz\.?\s*0\b")
_BASEMENT = re.compile(r"suteren|piwnic|podziemi|poziom\w*\s*-\s*(\d)|(?<!\w)-\s*(\d)\s*pi[ęe]tr")
_NUM = re.compile(r"(\d{1,2})\s*[.\-]?\s*(?:pi[ęe]tr\w*|kondygnacj\w*|p\b)|pi[ęe]tr\w*\s*(?:nr\s*)?(\d{1,2})\b|poziom\w*\s*(\d{1,2})\b")
_ROM = re.compile(r"(?<!\w)([IVXL]{1,5})\s*\.?\s*(?i:pi[ęe]tr\w*)|(?i:pi[ęe]tr\w*)\s+([IVXL]{1,5})(?!\w)")  # uppercase only: lowercase "i" is "and"
_ORDW = re.compile(r"\b(" + "|".join(_ORD) + r")\w*\s+pi[ęe]tr\w*")


def floor_from_text(text):
    t = (text or "").lower()
    if not t.strip() or _HALF.search(t):
        return None
    found = set()
    if _GROUND.search(t):
        found.add(0)
    for m in _BASEMENT.finditer(t):
        n = m.group(1) or m.group(2)
        found.add(-int(n) if n else -1)
    for m in _NUM.finditer(t):
        n = next(g for g in m.groups() if g)
        found.add(int(n))
    for m in _ROM.finditer(text or ""):
        found.add(_roman(m.group(1) or m.group(2)))
    for m in _ORDW.finditer(t):
        for k, v in _ORD.items():
            if re.match(k, m.group(1)):
                found.add(v)
    return found.pop() if len(found) == 1 else None
