import numpy as np

from pipeline.placement import active_at, greedy, sparse


def aed(status="scheduled", schedule=None, verified=True):
    return {"status": status, "schedule": schedule or {}, "verified": verified}


def test_active_only_inside_verified_hours():
    office = aed(schedule={"mon": [["08:00", "16:00"]], "sat": []})
    assert active_at(office, "mon", 8 * 60) and not active_at(office, "mon", 16 * 60)
    assert not active_at(office, "sat", 12 * 60)
    assert active_at(aed("24/7"), "sun", 3 * 60)
    assert not active_at(aed("24/7", verified=False), "sun", 3 * 60)


def test_greedy_takes_the_biggest_uncovered_group_first_and_skips_covered_ones():
    # three sites over four cells: site 0 covers cells 0-1, site 1 cells 1-2, site 2 cell 3
    matrix = sparse([[0, 1], [1, 2], [3]], 4)
    weights = np.array([10.0, 30.0, 20.0, 5.0])
    picks = greedy(matrix, weights, weights * 0.2, np.zeros(4, dtype=bool), 3)
    assert [p[0] for p in picks] == [1, 0, 2]
    assert [p[1] for p in picks] == [50, 10, 5]  # site 0's cell 1 was already covered by site 1
    assert picks[-1][3] == 100.0


def test_greedy_starts_from_what_is_already_covered():
    matrix = sparse([[0, 1], [2]], 3)
    weights = np.array([10.0, 10.0, 10.0])
    covered = np.array([True, True, False])
    assert [p[0] for p in greedy(matrix, weights, weights, covered, 5)] == [1]
