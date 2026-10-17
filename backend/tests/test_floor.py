import unittest

from pipeline.floor import floor_from_text as f


class FloorFromText(unittest.TestCase):
    def test_known_floors(self):
        cases = {
            "Urządzenie znajduje się w holu głównym na parterze budynku": 0,
            "Przy wejściu głównym do szkoły na poziomie przyziemia.": 0,
            "poziom \"O\" przy głównym wejściu": 0,
            "AED znajduje się na 1 piętrze obok windy": 1,
            "II piętro na głównym korytarzu": 2,
            "gabinet, piętro I": 1,
            "XX piętro PKiN - hol przy windach": 20,
            "poziom -1": -1,
        }
        for text, want in cases.items():
            self.assertEqual(f(text), want, text)

    def test_never_guesses(self):
        for text in [
            "Przy wejściu na półpiętrze.",              # mezzanine
            "dwa urządzenia na parterze i II piętrze",  # two devices on two floors
            "hol i piętro",                             # lowercase "i" is a conjunction
            "Hall przy głównym wejściu do budynku.",    # no floor stated
            "",
            None,
        ]:
            self.assertIsNone(f(text), text)


if __name__ == "__main__":
    unittest.main()
