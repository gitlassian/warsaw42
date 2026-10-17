import unittest
from datetime import date

from pipeline.seed_sql import easter, polish_holidays, q, review, weekly


def record(**kw):
    base = {"status": "scheduled", "parse_source": "regex", "suspicious": False, "assumed": [],
            "schedule": {k: [["08:00", "16:00"]] for k in ("mon", "tue", "wed", "thu", "fri", "sat", "sun")}}
    return {**base, **kw}


class Weekly(unittest.TestCase):
    def test_minutes_and_iso_days(self):
        w = weekly({"mon": [["08:00", "24:00"]], "sun": [["00:00", "06:30"]]})
        self.assertEqual(w["1"], [[480, 1440]])
        self.assertEqual(w["7"], [[0, 390]])
        self.assertEqual(w["3"], [])

    def test_overlapping_intervals_are_merged(self):
        self.assertEqual(weekly({"tue": [["12:00", "16:00"], ["08:00", "13:00"]]})["2"], [[480, 960]])

    def test_empty_interval_is_dropped(self):
        self.assertEqual(weekly({"wed": [["10:00", "10:00"]]})["3"], [])


class Review(unittest.TestCase):
    def test_full_regex_week_is_validated(self):
        self.assertEqual(review(record(), False), ("validated", []))

    def test_missing_days_are_partial(self):
        r = record(schedule={"mon": [["08:00", "16:00"]]})
        self.assertEqual(review(r, False), ("validated_partial", []))

    def test_guesses_need_review(self):
        self.assertEqual(review(record(parse_source="llm:x"), False)[0], "needs_review")
        self.assertEqual(review(record(assumed=["weekdays_assumed"]), False)[0], "needs_review")

    def test_metro_hours_are_a_source_rule(self):
        self.assertEqual(review(record(assumed=["metro_hours_assumed"]), False), ("validated_partial", ["metro_hours@1"]))

    def test_flagged_247_needs_review_unless_trusted(self):
        r = record(status="24/7", parse_source="availability_field", suspicious=True)
        self.assertEqual(review(r, False)[0], "needs_review")
        self.assertEqual(review(r, True)[0], "validated")


class Holidays(unittest.TestCase):
    def test_easter(self):
        self.assertEqual(easter(2026), date(2026, 4, 5))
        self.assertEqual(easter(2027), date(2027, 3, 28))

    def test_movable_feasts_2026(self):
        names = {n: d for d, n in polish_holidays(2026)}
        self.assertEqual(names["Boże Ciało"], date(2026, 6, 4))
        self.assertEqual(names["Zielone Świątki"], date(2026, 5, 24))


class Literals(unittest.TestCase):
    def test_quoting(self):
        self.assertEqual(q("Przedszkole \"Leśna Bajka\" O'Brien"), "'Przedszkole \"Leśna Bajka\" O''Brien'")
        self.assertEqual(q(None), "NULL")
        self.assertEqual(q(True), "true")
