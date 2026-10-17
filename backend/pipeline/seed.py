"""Generate backend/supabase/seed.sql from the data snapshot.

    python3 backend/pipeline/seed.py [--out backend/supabase/seed.sql]

Inputs
  backend/data/{raw,out,cache}      pipeline results (committed)
  data/{aed,geo,population,bo}      heavy pre-event snapshot (NOT committed, see data/README.md)

The generated seed.sql IS committed, so the heavy folders are only needed to regenerate it.
Apply order is handled inside the file. It targets a fresh database (supabase db reset).

Trust rules (PLAN.md section 5), applied when choosing aed_hours.review_status:
  * 24/7 straight from the city's availability flag            -> validated
  * regex result with an explicit day for every interval       -> validated_partial (or validated if all 7 days)
  * anything that rests on an assumption (time without days,
    "metro opening hours") or on the LLM                       -> needs_review  (the API reports it as unknown)
  * days not mentioned in the text stay `unknown`, never `closed`
"""
import argparse
import ast
import csv
import hashlib
import json
import math
import os
import re
import sys
import unicodedata
import uuid
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(BACKEND)
B = lambda *p: os.path.join(BACKEND, "data", *p)
H = lambda *p: os.path.join(REPO, "data", *p)
NS = uuid.UUID("6f1c3a52-0a43-4a8e-9a0e-5f0d6d3c2b11")  # fixed namespace: the same source id always gets the same uuid
KX = 111320 * math.cos(math.radians(52.23))
KY = 110540
DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
log = lambda *a: print(*a, file=sys.stderr)


# ------------------------------------------------------------------ SQL literals
def q(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def qj(obj):
    s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    assert "$j$" not in s
    return f"$j${s}$j$::jsonb"


def qarr(items, typ="text"):
    return f"ARRAY[{','.join(q(i) for i in items)}]::{typ}[]" if items else f"'{{}}'::{typ}[]"


def geom(geojson):
    return f"ST_SetSRID(ST_GeomFromGeoJSON({q(json.dumps(geojson, separators=(',', ':')))}), 4326)"


def aed_uuid(source_id):
    return str(uuid.uuid5(NS, f"aed:{source_id}"))


# ------------------------------------------------------------------ helpers
def md5(s):
    return hashlib.md5((s or "").encode()).hexdigest()


def norm(s):
    s = unicodedata.normalize("NFKD", (s or "").lower().replace("ł", "l"))
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"\b(ulica|ul|aleja|aleje|al|plac|pl|os|osiedle|rondo|skwer|bulwar)\b\.?", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


def last_word(s):
    words = [norm(w) for w in re.split(r"[\s\"„”“.]+", s or "")]
    words = [w for w in words if len(w) >= 4 and not w.isdigit()]
    return words[-1] if words else ""


def nb(s):
    return re.sub(r"\s", "", (s or "").lower())


def easter(y):  # anonymous Gregorian algorithm
    a, b, c = y % 19, y // 100, y % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    mo, da = divmod(h + l - 7 * m + 114, 31)
    return date(y, mo, da + 1)


def holidays(y):
    e = easter(y)
    fixed = [(1, 1, "Nowy Rok"), (1, 6, "Trzech Króli"), (5, 1, "Święto Pracy"), (5, 3, "Święto Konstytucji 3 Maja"),
             (8, 15, "Wniebowzięcie NMP"), (11, 1, "Wszystkich Świętych"), (11, 11, "Święto Niepodległości"),
             (12, 24, "Wigilia"), (12, 25, "Boże Narodzenie"), (12, 26, "Drugi dzień Bożego Narodzenia")]
    out = [(date(y, m, d), n) for m, d, n in fixed]
    out += [(e, "Wielkanoc"), (e + timedelta(1), "Poniedziałek Wielkanocny"), (e + timedelta(49), "Zielone Świątki"),
            (e + timedelta(60), "Boże Ciało")]
    return sorted(out)


# ------------------------------------------------------------------ EPSG:3035 (ETRS89-LAEA) inverse, for the GUS grid
def laea_inverse(E, N):
    a, e2 = 6378137.0, 0.00669438002290
    e = math.sqrt(e2)
    phi0, lam0, FE, FN = math.radians(52), math.radians(10), 4321000.0, 3210000.0
    qf = lambda s: (1 - e2) * (s / (1 - e2 * s * s) - (1 / (2 * e)) * math.log((1 - e * s) / (1 + e * s)))
    qp, q0 = qf(1.0), qf(math.sin(phi0))
    beta0 = math.asin(q0 / qp)
    Rq = a * math.sqrt(qp / 2)
    D = a * math.cos(phi0) / math.sqrt(1 - e2 * math.sin(phi0) ** 2) / (Rq * math.cos(beta0))
    x, y = E - FE, N - FN
    rho = math.hypot(x / D, D * y)
    C = 2 * math.asin(rho / (2 * Rq))
    beta = math.asin(math.cos(C) * math.sin(beta0) + D * y * math.sin(C) * math.cos(beta0) / rho)
    lam = lam0 + math.atan2(x * math.sin(C), D * rho * math.cos(beta0) * math.cos(C) - D * D * y * math.sin(beta0) * math.sin(C))
    phi = (beta + (e2 / 3 + 31 * e2**2 / 180 + 517 * e2**3 / 5040) * math.sin(2 * beta)
           + (23 * e2**2 / 360 + 251 * e2**3 / 3780) * math.sin(4 * beta) + (761 * e2**3 / 45360) * math.sin(6 * beta))
    return math.degrees(lam), math.degrees(phi)


def read_dbf(path):
    import struct
    with open(path, "rb") as f:
        h = f.read(32)
        n, hl, rl = struct.unpack("<IHH", h[4:12])
        fields = []
        while True:
            d = f.read(32)
            if d[0] == 0x0D:
                break
            fields.append((d[:11].split(b"\0")[0].decode(), d[16]))
        f.seek(hl)
        for _ in range(n):
            r = f.read(rl)
            pos, row = 1, {}
            for name, ln in fields:
                row[name] = r[pos:pos + ln].decode("latin1").strip()
                pos += ln
            yield row


# ------------------------------------------------------------------ districts from raw OSM relations
def build_districts():
    els = json.load(open(H("geo", "osm_dzielnice_raw.json")))["elements"]
    out = []
    for rel in els:
        ways = {"outer": [], "inner": []}
        for m in rel.get("members", []):
            if m["type"] == "way" and m.get("geometry") and m["role"] in ways:
                ways[m["role"]].append([(p["lon"], p["lat"]) for p in m["geometry"]])

        def rings(segs):
            segs, done = [s[:] for s in segs], []
            while segs:
                cur = segs.pop(0)
                while cur[0] != cur[-1]:
                    for i, s in enumerate(segs):
                        if s[0] == cur[-1]:
                            cur += s[1:]
                        elif s[-1] == cur[-1]:
                            cur += s[::-1][1:]
                        elif s[-1] == cur[0]:
                            cur = s[:-1] + cur
                        elif s[0] == cur[0]:
                            cur = s[::-1][:-1] + cur
                        else:
                            continue
                        segs.pop(i)
                        break
                    else:
                        raise ValueError("ring does not close")
                done.append(cur)
            return done

        try:
            outer, inner = rings(ways["outer"]), rings(ways["inner"])
        except ValueError:
            log("district skipped (open ring):", rel["tags"].get("name"))
            continue

        def inside(pt, ring):
            x, y, c = pt[0], pt[1], False
            for i in range(len(ring) - 1):
                (x1, y1), (x2, y2) = ring[i], ring[i + 1]
                if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                    c = not c
            return c

        polys = [[o] for o in outer]
        for h in inner:
            for p in polys:
                if inside(h[0], p[0]):
                    p.append(h)
                    break
        rnd = lambda r: [[round(x, 6), round(y, 6)] for x, y in r]
        out.append({"name": rel["tags"]["name"], "osm_relation": rel["id"],
                    "geojson": {"type": "MultiPolygon", "coordinates": [[rnd(r) for r in p] for p in polys]}})
    return out


# ------------------------------------------------------------------ hours -> review status
def review_status(rec):
    src, status, assumed = rec["parse_source"], rec["status"], rec["assumed"]
    if status == "unknown":
        return "pending" if src == "no_text" else "needs_review"
    if src == "availability_field":
        return "needs_review" if any("limited hours" in r for r in rec["suspicious_reasons"]) else "validated"
    if assumed or src.startswith("llm"):
        return "needs_review"
    days = sum(1 for d in DAYS if rec["schedule"][d])
    return "validated" if days == 7 else "validated_partial"


def parser_version(rec):
    return "llm@1:" + rec["parse_source"].split(":", 1)[1] if rec["parse_source"].startswith("llm:") else "pipeline@1"


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(BACKEND, "supabase", "seed.sql"))
    args = ap.parse_args()
    S = []  # SQL statements, in dependency order
    add = S.append

    raw_path = B("raw", "scb_aed_list.json")
    raw_bytes = open(raw_path, "rb").read()
    raw_list = json.loads(raw_bytes)
    raw = {r["properties"]["defibrillator_id"]: r for r in raw_list}
    aed = json.load(open(B("out", "aed.json")))
    bld = json.load(open(B("out", "aed_building.json")))
    cache = json.load(open(B("cache", "hours_cache.json")))
    stats = Counter()

    # --- sources, holidays
    add("INSERT INTO data_source (id, name, attribution, license_url) VALUES "
        "('warsaw_open_data','Warsaw Open Data: AED locations (Stołeczne Centrum Bezpieczeństwa)',"
        "'Dane: m.st. Warszawa, Stołeczne Centrum Bezpieczeństwa (dane.um.warszawa.pl), CC BY','https://creativecommons.org/licenses/by/4.0/'),"
        "('openstreetmap','OpenStreetMap','© OpenStreetMap contributors (ODbL)','https://www.openstreetmap.org/copyright'),"
        "('gus_census_2021','GUS National Census 2021, 1 km population grid','Dane: Główny Urząd Statystyczny, NSP 2021',NULL);")
    hol = [h for y in (2026, 2027) for h in holidays(y)]
    add("INSERT INTO public_holiday (on_date, name) VALUES " + ",".join(f"({q(d.isoformat())},{q(n)})" for d, n in hol) + ";")

    # --- districts and service area (rings assembled from OSM ways)
    dist = build_districts()
    for d in dist:
        add(f"INSERT INTO district (name, osm_relation, boundary) VALUES ({q(d['name'])},{d['osm_relation']},"
            f"ST_Multi(ST_CollectionExtract(ST_MakeValid({geom(d['geojson'])}),3)));")
    add("INSERT INTO service_area (source, boundary) SELECT 'union of OSM district boundaries (admin_level 9)', "
        "ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(boundary)),3)) FROM district;")
    stats["districts"] = len(dist)

    # --- buildings that AEDs were matched to (footprints from the city layer)
    need = {b["building_id"] for b in bld.values() if b.get("building_id")}
    foot = {}
    for f in json.load(open(H("geo", "budynki.geojson")))["features"]:
        p = f["properties"]
        if p["ID_BUDYNKU"] in need and f.get("geometry"):
            g = f["geometry"]
            g["coordinates"] = json.loads(json.dumps(g["coordinates"]), parse_float=lambda x: round(float(x), 6))
            foot[p["ID_BUDYNKU"]] = (p, g)
    for bid, (p, g) in sorted(foot.items()):
        add(f"INSERT INTO building (id, floors_above, floors_below, kind, footprint) VALUES "
            f"({q(bid)},{q(p.get('KONDYGNACJE_NADZIEMNE'))},{q(p.get('KONDYGNACJE_PODZIEMNE'))},{q(p.get('RODZAJ'))},"
            f"ST_MakeValid({geom(g)}));")
    stats["buildings"] = len(foot)

    # --- addresses, matched against official address points (exact name, then surname + number)
    pts = defaultdict(list)
    by_last = defaultdict(list)
    for f in json.load(open(H("geo", "punkty_adresowe.geojson")))["features"]:
        p, c = f["properties"], f["geometry"]["coordinates"]
        rec = (c[0], c[1], p["NAZWA_ULICY"], p["ID_IIP"])
        pts[(norm(p["NAZWA_ULICY"]), nb(p["NUMER_PORZADKOWY"]))].append(rec)
        by_last[(last_word(p["NAZWA_ULICY"]), nb(p["NUMER_PORZADKOWY"]))].append(rec)
    addr, addr_rows = {}, []
    for a in aed:
        p = raw[a["id"]]["properties"]
        key = (p["location_street"], p["location_building"], p["location_postcode"])
        if key in addr:
            continue
        lon, lat = a["lon"], a["lat"]
        cands = pts.get((norm(p["location_street"]), nb(p["location_building"]))) or []
        how = "exact"
        if not cands:
            cands, how = by_last.get((last_word(p["location_street"]), nb(p["location_building"]))) or [], "surname"
        best, off = None, None
        if cands:
            best = min(cands, key=lambda t: math.hypot((lon - t[0]) * KX, (lat - t[1]) * KY))
            off = math.hypot((lon - best[0]) * KX, (lat - best[1]) * KY)
            if how == "surname" and off > 300:  # a surname + number can belong to another street: only accept close ones
                best, off = None, None
        st = "no_match" if best is None else ("matched" if off <= 100 else "far")
        stats["address_" + st] += 1
        addr[key] = (len(addr) + 1, st)
        addr_rows.append(f"({len(addr)},{q(p['location_street'])},{q(best[2] if best else None)},{q(p['location_building'])},"
                         f"{q(p['location_postcode'])},{q(p['location_city'] or 'Warszawa')},{q(round(best[0], 7) if best else None)},"
                         f"{q(round(best[1], 7) if best else None)},{q(best[3] if best else None)},{q(st)},{q(round(off, 1) if off is not None else None)})")
    add("INSERT INTO address (id, street_raw, street_official, building_no, postcode, city, official_lon, official_lat, "
        "official_id, match, match_offset_m) VALUES\n" + ",\n".join(addr_rows) + ";")
    add("SELECT setval(pg_get_serial_sequence('address','id'), (SELECT max(id) FROM address));")

    # --- import provenance
    snap_sha = hashlib.sha256(raw_bytes).hexdigest()
    fetched = datetime.fromtimestamp(os.path.getmtime(raw_path), timezone.utc).isoformat(timespec="seconds")
    add(f"INSERT INTO refresh_run (id, started_at, finished_at, status, total, added, removed, changed, quarantined, llm_calls) "
        f"VALUES (1,{q(fetched)},{q(fetched)},'ok',{len(raw)},{len(raw)},0,0,0,{len(cache)});")
    add(f"INSERT INTO source_snapshot (run_id, fetched_at, record_count, sha256, complete, payload) "
        f"VALUES (1,{q(fetched)},{len(raw)},{q(snap_sha)},true,{qj(raw_list)});")
    add("INSERT INTO dataset_version (id, cause, refresh_run_id) VALUES (1,'import',1);")
    add("SELECT setval(pg_get_serial_sequence('refresh_run','id'),1), setval(pg_get_serial_sequence('dataset_version','id'),1);")

    # --- AEDs
    rows = []
    for a in aed:
        p = raw[a["id"]]["properties"]
        key = (p["location_street"], p["location_building"], p["location_postcode"])
        pub = {"Publiczny": "public", "Prywatny": "restricted"}.get(p.get("device_public_access"), "unknown")
        src_hash = hashlib.md5(json.dumps(raw[a["id"]], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        bid = bld.get(a["id"], {}).get("building_id")
        rows.append(f"({q(aed_uuid(a['id']))},{q(a['id'])},{q(a['name'])},{addr[key][0]},{a['lon']!r},{a['lat']!r},{q(a['in_building'])},"
                    f"{q(a['in_footprint'])},{q(a['floor'])},{q(a['floor_source'])},{q(a['location_description'])},"
                    f"{q(bid if bid in foot else None)},{q(pub)},{q(p.get('device_public_access'))},{q(p.get('device_availability'))},"
                    f"{q(p.get('device_access_description') or None)},{q(p.get('device_manufacturer'))},{q(p.get('device_specifications'))},{q(src_hash)})")
    add("INSERT INTO aed (id, source_id, object_name, address_id, lon, lat, in_building, in_footprint, floor, floor_source, "
        "location_description, building_id, public_access, public_access_raw, availability_raw, access_text, manufacturer, "
        "has_specifications, source_hash) VALUES\n" + ",\n".join(rows) + ";")

    # districts are set after the AEDs exist: addresses without an official point use the AED coordinate
    add("UPDATE address a SET district_id = (SELECT d.id FROM district d WHERE ST_Covers(d.boundary, "
        "ST_SetSRID(ST_MakePoint(coalesce(a.official_lon, (SELECT x.lon FROM aed x WHERE x.address_id = a.id LIMIT 1)), "
        "coalesce(a.official_lat, (SELECT x.lat FROM aed x WHERE x.address_id = a.id LIMIT 1))), 4326)) LIMIT 1);")

    # --- hours: aed_hours, explicit day states, intervals
    hrows, drows, srows = [], [], []
    for hid, a in enumerate(aed, 1):
        p = raw[a["id"]]["properties"]
        text = p.get("device_access_description") or None
        rs = review_status(a)
        stats["hours_" + rs] += 1
        if a["parse_source"] == "availability_field":
            evidence = text or f"device_availability = {p.get('device_availability')}"
        else:
            evidence = a["raw_hours"] if a["status"] == "scheduled" else None
        note = a["note"]
        if a["assumed"]:
            note = "; ".join(filter(None, [note, "assumption, not stated in the source: " + ",".join(a["assumed"])]))
        if a["status"] == "scheduled" and not text and a["raw_hours"]:
            note = "; ".join(filter(None, [note, "hours text found in device_availability, device_access_description is empty"]))
        hrows.append(f"({hid},{q(aed_uuid(a['id']))},{q(a['status'])},{q(text)},{q(md5(text))},{q(a['osm_hours'] if a['status'] != 'unknown' else None)},"
                     f"{q(evidence)},{q(a['parse_source'] if not a['parse_source'] in ('no_text', 'unparsed') else 'regex')},"
                     f"{q(parser_version(a))},{q(rs)},{q(note or None)})")
        if a["status"] == "scheduled":
            for i, d in enumerate(DAYS, 1):
                iv = a["schedule"][d]
                drows.append(f"({hid},{i},{q('open_intervals' if iv else 'unknown')})")
                for s, e in iv:
                    srows.append(f"({hid},{i},{int(s[:2]) * 60 + int(s[3:])},{int(e[:2]) * 60 + int(e[3:])})")
    add("INSERT INTO aed_hours (id, aed_id, status, source_text, source_text_hash, osm_hours, evidence, parse_source, "
        "parser_version, review_status, note) VALUES\n" + ",\n".join(hrows) + ";")
    add("SELECT setval(pg_get_serial_sequence('aed_hours','id'), (SELECT max(id) FROM aed_hours));")
    add("INSERT INTO aed_day_state (hours_id, dow, state) VALUES " + ",".join(drows) + ";")
    add("INSERT INTO aed_schedule (hours_id, dow, start_min, end_min) VALUES " + ",".join(srows) + ";")

    # --- LLM cache (same key the pipeline uses: stripped text, parser version carries the model)
    crow = []
    for text, c in sorted(cache.items()):
        model = c["source"].split(":", 1)[1] if ":" in c["source"] else None
        crow.append(f"({q(md5(text))},{q('llm@1:' + (model or ''))},{q(text)},{q(c['status'])},{qj(c['schedule'])},{q(c['source'])},{q(model)},{q(c.get('note') or None)})")
    add("INSERT INTO hours_cache (source_text_hash, parser_version, source_text, status, schedule, source, model, note) VALUES\n" + ",\n".join(crow) + ";")

    # --- photos: originals stay private; width/height/public_file_name describe the EXIF-free copy made by photos.py
    from PIL import Image
    manifest = json.load(open(H("aed", "photos_public", "manifest.json")))["photos"]
    prow = []
    for fn in sorted(os.listdir(H("aed", "photos"))):
        sid = os.path.splitext(fn)[0]
        if sid not in raw:
            continue
        path = H("aed", "photos", fn)
        sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
        ex = Image.open(path).getexif()
        taken = None
        dt = (ex.get(306) or "").strip("\x00 ")
        try:
            taken = datetime.strptime(dt, "%Y:%m:%d %H:%M:%S").replace(tzinfo=timezone.utc).isoformat()
        except ValueError:
            pass
        make = (ex.get(271) or "").strip("\x00 ") or None
        pub = manifest.get(sid)
        prow.append(f"({q(aed_uuid(sid))},{q('photos/' + fn)},{q(pub['file'] if pub else None)},{q(sha)},{q(pub['width'] if pub else None)},"
                    f"{q(pub['height'] if pub else None)},{q(taken)},{q(make)},{q(bool(ex.get(34853)))})")
    add("INSERT INTO aed_photo (aed_id, file_name, public_file_name, sha256, width, height, taken_at, camera_make, exif_has_gps) VALUES\n" + ",\n".join(prow) + ";")
    stats["photos"] = len(prow)

    # --- OSM AEDs, matched to the nearest city AED within 50 m
    cx = [(a["lon"] * KX, a["lat"] * KY, a["id"]) for a in aed]
    orow = []
    for e in json.load(open(H("aed", "osm_aed_warszawa.json")))["elements"]:
        lon, lat = (e["lon"], e["lat"]) if "lon" in e else (e["center"]["lon"], e["center"]["lat"])
        t = e.get("tags", {})
        d, sid = min((math.hypot(lon * KX - x, lat * KY - y), i) for x, y, i in cx)
        lv = t.get("level", "").strip()
        orow.append(f"({e['id']},{q(e['type'])},{lon!r},{lat!r},{q(int(lv) if re.fullmatch(r'-?\d{1,2}', lv) else None)},{q(t.get('opening_hours'))},"
                    f"{q(t.get('access'))},{q({'yes': True, 'no': False}.get(t.get('indoor')))},{q(t.get('operator'))},{qj(t)},"
                    f"{q(aed_uuid(sid) if d <= 50 else None)},{q(round(d, 1) if d <= 50 else None)})")
    add("INSERT INTO osm_aed (osm_id, osm_type, lon, lat, level, opening_hours, access, indoor, operator, tags, matched_aed_id, match_dist_m) VALUES\n"
        + ",\n".join(orow) + ";")
    stats["osm_aed"] = len(orow)

    # --- audit flags
    coords = Counter((a["lon"], a["lat"]) for a in aed)
    flags = defaultdict(dict)
    for a in aed:
        i, f = a["id"], flags[a["id"]]
        for r in a["suspicious_reasons"]:
            f["247_indoors_unstaffed" if "staffed" in r else "247_but_limited_text"] = ("warning", r)
        if a["status"] == "unknown":
            f["hours_unknown"] = ("info", a["note"])
        if a["parse_source"].startswith("llm") and a["status"] != "unknown":
            f["hours_llm"] = ("info", "schedule came from the LLM; check against the source text")
        if a["assumed"]:
            f["hours_assumed"] = ("warning", "schedule rests on an assumption: " + ",".join(a["assumed"]))
        if coords[(a["lon"], a["lat"])] > 1:
            f["duplicate_coords"] = ("info", None)
        if (not a["in_building"]) and a["in_footprint"]:
            f["outdoor_in_footprint"] = ("info", "flagged outside but the point lies inside a building footprint")
        if i == "2487":
            f["detail_request_500"] = ("info", "the per-device API call returns 500")
    off = {}
    for a in aed:
        key = (raw[a["id"]]["properties"][k] for k in ("location_street", "location_building", "location_postcode"))
        off[a["id"]] = addr[tuple(key)][1]
    for i, st in off.items():
        if st == "far":
            flags[i]["coord_far_from_address"] = ("warning", "AED coordinate is more than 100 m from the official point of its own address")
        elif st == "no_match":
            flags[i]["address_no_match"] = ("info", None)
    frow = [f"({q(aed_uuid(i))},{q(c)},{q(s)},{q(d)})" for i, fl in flags.items() for c, (s, d) in fl.items()]
    add("INSERT INTO audit_flag (aed_id, code, severity, detail) VALUES\n" + ",\n".join(frow) + ";")
    stats["audit_flags"] = len(frow)

    # --- GUS population grid, cells whose centre lies inside Warsaw
    prow = []
    for r in read_dbf(H("population", "GRID_NSP2021_RES", "GRID_NSP2021_RES.dbf")):
        m = re.match(r"CRS3035RES1000mN(\d+)E(\d+)", r["CODE"])
        if not m:
            continue
        lon, lat = laea_inverse(int(m.group(2)) + 500, int(m.group(1)) + 500)
        if 20.8 < lon < 21.3 and 52.0 < lat < 52.4:
            num = lambda v: int(v) if v.isdigit() else None  # GUS masks small counts with "*****": that is NULL, not 0
            prow.append((r["CODE"], round(lon, 6), round(lat, 6), num(r["RES"]) or 0, num(r["RES_0_14"]), num(r["RES_15_64"]), num(r["RES_65_"])))
    add("INSERT INTO population_cell (code, lon, lat, residents, res_0_14, res_15_64, res_65_plus) VALUES\n"
        + ",\n".join(f"({q(c)},{lo},{la},{r},{q(a)},{q(b)},{q(c65)})" for c, lo, la, r, a, b, c65 in prow) + ";")
    add("DELETE FROM population_cell WHERE NOT is_inside_warsaw(lat, lon);")
    stats["population_cells_in_bbox"] = len(prow)

    # --- participatory budget (author names are not stored)
    bo = {}
    for fn in sorted(os.listdir(H("bo"))):
        if not re.match(r"bo_20\d\d_(zrealizowane|w_realizacji)\.json$", fn):
            continue
        for r in json.load(open(H("bo", fn))):
            bo.setdefault(int(r["id"]), r)
    lst = lambda v: ast.literal_eval(v) if isinstance(v, str) else (v or [])
    brow = []
    for i, r in sorted(bo.items()):
        pins = lst(r.get("pins"))
        lon = lat = None
        try:
            lon, lat = float(pins[0]["lng"]), float(pins[0]["lat"])
        except (IndexError, KeyError, TypeError, ValueError):
            try:
                lon, lat = float(r["lng"]), float(r["lat"])
            except (KeyError, TypeError, ValueError):
                pass
        is_aed = bool(re.search(r"\bAED\b|defibryl", f"{r.get('title') or ''} {r.get('shortDescription') or ''}", re.I))
        brow.append(f"({i},{q(r.get('editionName'))},{q(r.get('title'))},{q(r.get('shortDescription'))},{q(float(r['cost']) if r.get('cost') else None)},"
                    f"{q(lon)},{q(lat)},{q(r.get('mainRegionName'))},{qarr(lst(r.get('classifications')))},{q(is_aed)},{q(r.get('url'))})")
        stats["bo_aed_related"] += is_aed
    add("INSERT INTO bo_project (id, edition, title, short_desc, cost_pln, lon, lat, district, categories, is_aed_related, url) VALUES\n" + ",\n".join(brow) + ";")
    stats["bo_projects"] = len(brow)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("-- GENERATED by backend/pipeline/seed.py. Do not edit; regenerate instead.\n"
                "-- Seed for a fresh database (supabase db reset). Every statement runs in one transaction.\n"
                "BEGIN;\nSET search_path = public, extensions;\n\n" + "\n\n".join(S) + "\n\nCOMMIT;\n")
    log(f"wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB)")
    for k, v in sorted(stats.items()):
        log(f"  {k:28s} {v}")


if __name__ == "__main__":
    main()
