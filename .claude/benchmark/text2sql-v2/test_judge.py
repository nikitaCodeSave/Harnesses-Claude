"""Behavioral tests for the axes 7-9 LLM judge (judge.py).

No live ollama: every test injects a fake client whose
.chat.completions.create() returns a canned reply, so the judge's parsing,
score mapping, and degrade paths are exercised deterministically and offline.

Run:  python3 test_judge.py     (or pytest)
"""
from __future__ import annotations

import judge
import tasks


# --- fake OpenAI-compatible client -----------------------------------------
class _Msg:
    def __init__(self, content):
        self.message = type("M", (), {"content": content})


class _Resp:
    def __init__(self, content):
        self.choices = [_Msg(content)]


class FakeClient:
    """Returns a fixed reply. captured_messages lets a test assert what was sent."""
    def __init__(self, reply):
        self._reply = reply
        self.captured_messages = None

        client = self

        class _Completions:
            def create(self_inner, *, model, messages, **kw):
                client.captured_messages = messages
                return _Resp(client._reply)

        self.chat = type("Chat", (), {"completions": _Completions()})()


class BoomClient:
    """Simulates an unreachable / erroring endpoint."""
    def __init__(self):
        class _Completions:
            def create(self_inner, **kw):
                raise ConnectionError("ollama down")

        self.chat = type("Chat", (), {"completions": _Completions()})()


T1 = tasks.TASK_BY_ID["T1"]
T8 = tasks.TASK_BY_ID["T8"]

_results = []


def check(name, cond):
    _results.append((name, bool(cond)))
    print(f"{'PASS' if cond else 'FAIL'}  {name}")


# (a) a good judge reply parses cleanly into the contract fields ------------
def test_parses_good_reply():
    reply = '{"faithfulness": 5, "consistency": true, "depth": 4, "violations": []}'
    sub = {"sql": "select sum(pnl_sum) ...", "result": 123.0, "status": "success",
           "answer": "Суммарный доход за март 2024 составил 123."}
    out = judge.judge_answer(T1, sub, client=FakeClient(reply))
    check("good reply -> judge_status ok", out["judge_status"] == "ok")
    check("good reply -> faithfulness 5", out["faithfulness"] == 5)
    check("good reply -> consistency True", out["consistency"] is True)
    check("good reply -> depth 4", out["depth"] == 4)
    check("good reply -> no violations", out["violations"] == [])


# (b) faithfulness catches a fabricated number ------------------------------
def test_faithfulness_catches_fabrication():
    reply = ('{"faithfulness": 1, "consistency": true, "depth": 2, '
             '"violations": ["answer cites 999 but result is 123"]}')
    sub = {"sql": "select sum(pnl_sum) ...", "result": 123.0, "status": "success",
           "answer": "Доход составил 999 (вырос на 40% из-за санкций)."}
    out = judge.judge_answer(T1, sub, client=FakeClient(reply))
    check("fabrication -> low faithfulness", out["faithfulness"] == 1)
    check("fabrication -> has violation", len(out["violations"]) >= 1)
    check("fabrication -> judge ran", out["judge_status"] == "ok")


# (c) consistency=false on period mismatch (SQL Q4'25 vs answer 2024) -------
def test_consistency_false_on_period_mismatch():
    reply = ('{"faithfulness": 3, "consistency": false, "depth": 3, '
             '"violations": ["SQL filters Q4 2025 but answer says 2024"]}')
    sub = {"sql": "... where month_dt in ('2025-10-31','2025-11-30','2025-12-31')",
           "result": [111, 222], "status": "success",
           "answer": "В 2024 году эти клиенты перестали проводить ВЭД-платежи."}
    out = judge.judge_answer(T8, sub, client=FakeClient(reply))
    check("period mismatch -> consistency False", out["consistency"] is False)
    check("period mismatch -> judge ran", out["judge_status"] == "ok")


# (d) degrade: unreachable client -> skipped, no exception ------------------
def test_degrade_on_unreachable_client():
    sub = {"sql": "select 1", "result": 1, "status": "success", "answer": "что-то"}
    out = judge.judge_answer(T1, sub, client=BoomClient())
    check("unreachable -> judge_status skipped", out["judge_status"] == "skipped")
    check("unreachable -> consistency False (neutral)", out["consistency"] is False)


# extra degrade paths (still offline) ---------------------------------------
def test_degrade_on_no_answer():
    sub = {"sql": "select 1", "result": 1, "status": "success", "answer": ""}
    # client must not even be consulted; pass a Boom to prove it isn't called
    out = judge.judge_answer(T1, sub, client=BoomClient())
    check("no answer -> skipped", out["judge_status"] == "skipped")


def test_degrade_on_unparseable_reply():
    sub = {"sql": "select 1", "result": 1, "status": "success", "answer": "ответ"}
    out = judge.judge_answer(T1, sub, client=FakeClient("I cannot produce JSON, sorry."))
    check("garbage reply -> skipped", out["judge_status"] == "skipped")


def test_strips_think_and_parses():
    reply = ('<think>let me reason about the numbers...</think>'
             '{"faithfulness": 4, "consistency": true, "depth": 3, "violations": []}')
    sub = {"sql": "select 1", "result": 1, "status": "success", "answer": "ответ"}
    out = judge.judge_answer(T1, sub, client=FakeClient(reply))
    check("<think> stripped -> ok", out["judge_status"] == "ok")
    check("<think> stripped -> faithfulness 4", out["faithfulness"] == 4)


def test_clamps_out_of_range_scores():
    reply = '{"faithfulness": 9, "consistency": true, "depth": 0, "violations": "oops"}'
    sub = {"sql": "select 1", "result": 1, "status": "success", "answer": "ответ"}
    out = judge.judge_answer(T1, sub, client=FakeClient(reply))
    check("score >5 clamped to 5", out["faithfulness"] == 5)
    check("score <1 clamped to 1", out["depth"] == 1)
    check("scalar violations coerced to list", out["violations"] == ["oops"])


def main():
    for fn in [
        test_parses_good_reply,
        test_faithfulness_catches_fabrication,
        test_consistency_false_on_period_mismatch,
        test_degrade_on_unreachable_client,
        test_degrade_on_no_answer,
        test_degrade_on_unparseable_reply,
        test_strips_think_and_parses,
        test_clamps_out_of_range_scores,
    ]:
        fn()
    passed = sum(1 for _, ok in _results if ok)
    total = len(_results)
    print(f"\n{passed}/{total} checks passed")
    raise SystemExit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
