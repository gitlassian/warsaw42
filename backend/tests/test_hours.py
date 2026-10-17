import unittest

from pipeline.hours import is_open, parse_regex, to_osm, validate_schedule
from pipeline import llm_hours


def osm(text):
    r = parse_regex(text)
    return to_osm(r.schedule) if r else None


class RegexParser(unittest.TestCase):
    def test_common_formats(self):
        cases = {
            "dni powszednie 07:00-17:00": "Mo-Fr 07:00-17:00",
            "Poniedziałek - Piątek w godzinach od 8.30 do 15.30": "Mo-Fr 08:30-15:30",
            "poniedziałek - piątek od 7;00 do 20;00": "Mo-Fr 07:00-20:00",
            "Poniedziałek: godz. 8:00-18:00; Wtorek-Piątek: godz. 8:00-16:00": "Mo 08:00-18:00; Tu-Fr 08:00-16:00",
            "pon-pt 7:00-22:00, sb-nd 8:00-22:00": "Mo-Fr 07:00-22:00; Sa-Su 08:00-22:00",
            "8 - 20, 7 dni w tygodniu": "Mo-Su 08:00-20:00",
            "9:00-21:00, pon.- niedz.": "Mo-Su 09:00-21:00",
            "6,30-17,30": "Mo-Fr 06:30-17:30",
            "Całodobowo": "24/7",
        }
        for text, want in cases.items():
            self.assertEqual(osm(text), want, text)

    def test_time_only_assumes_weekdays_and_says_so(self):
        r = parse_regex("8-16")
        self.assertEqual(to_osm(r.schedule), "Mo-Fr 08:00-16:00")
        self.assertIn("weekdays_assumed", r.assumed)

    def test_metro_is_flagged_as_assumption(self):
        r = parse_regex("W godzinach otwarcia stacji metra")
        self.assertIn("metro_hours_assumed", r.assumed)

    def test_overnight_interval_is_split(self):
        r = parse_regex("pon-pt 22-6")
        self.assertEqual(r.schedule["mon"], [["22:00", "24:00"]])
        self.assertEqual(r.schedule["tue"], [["00:00", "06:00"], ["22:00", "24:00"]])
        self.assertTrue(validate_schedule(r.schedule))

    def test_ambiguous_text_goes_to_llm(self):
        for text in [
            "dni robocze- poniedziałek w godz.08.00-18.00, wtorek-piątek 08.00-16.00",  # day listed twice
            "W roku szkolnym 9-21, w wakacje i ferie 8-16",
            "poniedziałek - piątek 10-19, druga i czwarta sobota 10-15",
            "Pon-pt 8:00-21:00, sob, ndz, święta 8:00-19:00",
            "W godzinach pracy Punktu Obsługi Pasażerów.",
            "ograniczona",
            "",
        ]:
            self.assertIsNone(parse_regex(text), text)

    def test_is_open(self):
        s = parse_regex("pon-pt 8-16").schedule
        self.assertTrue(is_open(s, 0, 8 * 60))
        self.assertFalse(is_open(s, 0, 16 * 60))
        self.assertFalse(is_open(s, 5, 10 * 60))


class LlmFallback(unittest.TestCase):
    def test_invalid_llm_schedule_becomes_unknown(self):
        bad = {"status": "scheduled", "note": "",
               "schedule": {d: [{"start": "18:00", "end": "08:00"}] for d in
                            ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]}}
        self.assertEqual(llm_hours._to_parsed(bad, "m").status, "unknown")

    def test_cache_hit_needs_no_key(self):
        cache = {"x": {"status": "unknown", "schedule": {}, "source": "llm:m", "note": ""}}
        self.assertEqual(llm_hours.resolve("x", cache).source, "llm:m")

    def test_no_key_returns_unparsed(self):
        import os
        os.environ.pop("OPENAI_API_KEY", None)
        self.assertEqual(llm_hours.resolve("something odd", {}).source, "unparsed")


if __name__ == "__main__":
    unittest.main()
