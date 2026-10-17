from pipeline.osm_hours import parse


def test_weekdays_and_explicit_closed_weekend():
    p = parse("Mo-Fr 07:30-15:30; Sa,Su off")
    assert p.status == "scheduled"
    assert p.schedule["mon"] == [["07:30", "15:30"]] and p.schedule["fri"] == [["07:30", "15:30"]]
    assert p.schedule["sat"] == [] and p.schedule["sun"] == []


def test_unmentioned_days_are_closed_and_later_rules_override():
    p = parse("Mo-Fr 07:00-20:00; Sa 08:00-15:00; We 09:00-12:00")
    assert p.schedule["wed"] == [["09:00", "12:00"]]
    assert p.schedule["sat"] == [["08:00", "15:00"]] and p.schedule["sun"] == []


def test_split_day_and_rule_without_days():
    assert parse("Mo-Fr 08:00-12:00,13:00-16:00").schedule["tue"] == [["08:00", "12:00"], ["13:00", "16:00"]]
    assert parse("08:00-16:00").schedule["sun"] == [["08:00", "16:00"]]


def test_247():
    assert parse("24/7").status == "24/7"


def test_unsupported_syntax_is_refused():
    for text in ("Dec, Jan Mo-Sa 09:00-15:00; Feb Mo-Su 09:00-16:00", "Mo-Fr 08:00-16:00; PH off", "sunrise-sunset",
                 "Mo-Su 22:00-02:00", "Mo-Fr 08:00-16:00 open", "by appointment", "", None):
        assert parse(text) is None, text
