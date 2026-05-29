"""
Agent tests — all LLM calls are mocked, no real ollama needed.
Tests verify: end-to-end pipeline, retry logic, NO_SQL handling,
response format handling, and prompt quality.
"""
from unittest.mock import patch

import pytest

from nl2sql.agent import nl_to_sql
from nl2sql.prompt import build_system_prompt


# ---------------------------------------------------------------------------
# Prompt quality (no LLM needed)
# ---------------------------------------------------------------------------

class TestPromptQuality:
    def setup_method(self):
        self.prompt = build_system_prompt()

    def test_contains_avg_rule_for_balances(self):
        assert "AVG" in self.prompt

    def test_contains_balance_column_names(self):
        assert "CA_LCY_SUM" in self.prompt
        assert "DEP_SUM" in self.prompt

    def test_contains_fetch_first_rule(self):
        assert "FETCH FIRST" in self.prompt

    def test_contains_no_limit_warning(self):
        assert "LIMIT" in self.prompt

    def test_contains_no_sql_instruction(self):
        assert "NO_SQL" in self.prompt

    def test_contains_count_distinct(self):
        assert "COUNT(DISTINCT INN)" in self.prompt

    def test_contains_trunc_month_dt(self):
        assert "TRUNC(MONTH_DT" in self.prompt

    def test_contains_pnl_components(self):
        for col in ("PL_CA", "PL_DEP", "VED_SUM", "FX_MARGIN_RUB"):
            assert col in self.prompt, f"{col} missing from prompt"

    def test_contains_lifecycle_columns(self):
        assert "CREATE_DT" in self.prompt
        assert "CLOSE_DT" in self.prompt

    def test_contains_activity_flags(self):
        assert "ACT_1M" in self.prompt
        assert "ACT_3M" in self.prompt


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def with_llm(response: str):
    """Context manager: patch call_llm to always return `response`."""
    return patch("nl2sql.agent.call_llm", return_value=response)


def with_llm_seq(*responses):
    """Context manager: patch call_llm to return responses in order."""
    return patch("nl2sql.agent.call_llm", side_effect=list(responses))


# ---------------------------------------------------------------------------
# Core scenarios
# ---------------------------------------------------------------------------

class TestAgentScenarios:
    # --- aggregate / count ---
    def test_count_clients_current_month(self):
        sql = "SELECT COUNT(DISTINCT INN) FROM client_product WHERE TRUNC(MONTH_DT, 'MM') = TRUNC(SYSDATE, 'MM')"
        with with_llm(sql):
            result = nl_to_sql("Сколько клиентов в текущем месяце?")
        assert "COUNT(DISTINCT INN)" in result
        assert "TRUNC(MONTH_DT" in result

    # --- balance averaging ---
    def test_avg_balance_multi_month(self):
        sql = "SELECT AVG(CA_LCY_SUM) AS avg_ca FROM client_product WHERE TRUNC(MONTH_DT, 'MM') >= ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -3)"
        with with_llm(sql):
            result = nl_to_sql("Средний остаток на счетах за последние 3 месяца")
        assert "AVG" in result
        assert "CA_LCY_SUM" in result

    # --- top-N with FETCH FIRST ---
    def test_top_n_uses_fetch_first(self):
        sql = "SELECT INN, ORGANIZATION_NM, SUM(PNL_SUM) AS total_pnl FROM client_product GROUP BY INN, ORGANIZATION_NM ORDER BY total_pnl DESC FETCH FIRST 10 ROWS ONLY"
        with with_llm(sql):
            result = nl_to_sql("Топ-10 клиентов по доходу за 2024 год")
        assert "FETCH FIRST" in result
        assert "LIMIT" not in result

    # --- income structure ---
    def test_income_structure_breakdown(self):
        sql = (
            "SELECT SEG, SUM(PL_CA) AS pl_ca, SUM(PL_DEP) AS pl_dep, "
            "SUM(FX_MARGIN_RUB) AS fx, SUM(PNL_SUM) AS total "
            "FROM client_product WHERE EXTRACT(YEAR FROM MONTH_DT) = 2024 GROUP BY SEG"
        )
        with with_llm(sql):
            result = nl_to_sql("Структура дохода по сегментам за 2024 год")
        assert "PNL_SUM" in result or "PL_CA" in result

    # --- lifecycle ---
    def test_clients_opened_in_year(self):
        sql = "SELECT COUNT(DISTINCT INN) FROM client_product WHERE EXTRACT(YEAR FROM CREATE_DT) = 2024"
        with with_llm(sql):
            result = nl_to_sql("Сколько клиентов открылось в 2024 году?")
        assert "CREATE_DT" in result

    def test_active_clients_filter(self):
        sql = "SELECT COUNT(DISTINCT INN) FROM client_product WHERE CLOSE_DT IS NULL AND TRUNC(MONTH_DT,'MM') = TRUNC(SYSDATE,'MM')"
        with with_llm(sql):
            result = nl_to_sql("Сколько активных клиентов на текущую дату?")
        assert "CLOSE_DT IS NULL" in result

    # --- activity flags ---
    def test_activity_flag(self):
        sql = "SELECT COUNT(DISTINCT INN) FROM client_product WHERE ACT_1M = 1 AND TRUNC(MONTH_DT,'MM') = ADD_MONTHS(TRUNC(SYSDATE,'MM'),-1)"
        with with_llm(sql):
            result = nl_to_sql("Сколько клиентов было активно в прошлом месяце?")
        assert "ACT_1M" in result or "ACT_3M" in result

    # --- period comparison ---
    def test_period_comparison_case_when(self):
        sql = (
            "SELECT "
            "SUM(CASE WHEN TRUNC(MONTH_DT,'MM')=DATE '2024-01-01' THEN PNL_SUM ELSE 0 END) AS jan, "
            "SUM(CASE WHEN TRUNC(MONTH_DT,'MM')=DATE '2024-02-01' THEN PNL_SUM ELSE 0 END) AS feb "
            "FROM client_product WHERE TRUNC(MONTH_DT,'MM') IN (DATE '2024-01-01',DATE '2024-02-01')"
        )
        with with_llm(sql):
            result = nl_to_sql("Сравни доход января и февраля 2024")
        assert "PNL_SUM" in result
        assert "CASE WHEN" in result or "GROUP BY" in result

    # --- FX ---
    def test_fx_volume_query(self):
        sql = "SELECT SUM(FX_VOLUME_RUB) AS fx_vol, SUM(FX_CNT) AS fx_cnt FROM client_product WHERE TRUNC(MONTH_DT,'MM') = DATE '2024-06-01'"
        with with_llm(sql):
            result = nl_to_sql("Объём FX-конверсий за июнь 2024")
        assert "FX_VOLUME_RUB" in result or "FX_CNT" in result

    # --- group / segment breakdown ---
    def test_segment_breakdown(self):
        sql = "SELECT SEG, COUNT(DISTINCT INN) AS cnt FROM client_product WHERE TRUNC(MONTH_DT,'MM') = TRUNC(SYSDATE,'MM') GROUP BY SEG"
        with with_llm(sql):
            result = nl_to_sql("Распределение клиентов по сегментам в текущем месяце")
        assert "SEG" in result
        assert "GROUP BY" in result


# ---------------------------------------------------------------------------
# NO_SQL handling
# ---------------------------------------------------------------------------

class TestNoSQL:
    def test_irrelevant_question_weather(self):
        with with_llm("NO_SQL"):
            result = nl_to_sql("Какая сегодня погода в Москве?")
        assert result == "NO_SQL"

    def test_irrelevant_question_exchange_rate(self):
        with with_llm("NO_SQL"):
            result = nl_to_sql("Курс доллара на сегодня")
        assert result == "NO_SQL"

    def test_no_sql_in_sentence(self):
        with with_llm("Этот вопрос нельзя ответить — NO_SQL"):
            result = nl_to_sql("Кто директор банка?")
        assert result == "NO_SQL"

    def test_no_sql_in_markdown_block(self):
        with with_llm("```\nNO_SQL\n```"):
            result = nl_to_sql("Список сотрудников")
        assert result == "NO_SQL"


# ---------------------------------------------------------------------------
# Response format handling
# ---------------------------------------------------------------------------

class TestResponseFormats:
    def test_sql_in_markdown_extracted(self):
        good_sql = "SELECT COUNT(*) FROM client_product"
        with with_llm(f"Вот запрос:\n```sql\n{good_sql}\n```"):
            result = nl_to_sql("Сколько записей?")
        assert result == good_sql

    def test_sql_with_preamble_extracted(self):
        good_sql = "SELECT COUNT(DISTINCT INN) FROM client_product"
        with with_llm(f"Ответ на вопрос:\n{good_sql}"):
            result = nl_to_sql("Сколько клиентов?")
        assert result == good_sql

    def test_trailing_semicolon_removed(self):
        with with_llm("SELECT COUNT(*) FROM client_product;"):
            result = nl_to_sql("Сколько записей?")
        assert not result.endswith(";")

    def test_limit_fixed_to_fetch_first(self):
        with with_llm("SELECT * FROM client_product ORDER BY PNL_SUM DESC LIMIT 5"):
            result = nl_to_sql("Топ-5 клиентов")
        assert "FETCH FIRST 5 ROWS ONLY" in result
        assert "LIMIT" not in result


# ---------------------------------------------------------------------------
# Retry logic
# ---------------------------------------------------------------------------

class TestRetryLogic:
    def test_retry_after_unparseable_response(self):
        good_sql = "SELECT COUNT(DISTINCT INN) FROM client_product"
        with with_llm_seq("ничего полезного, просто текст", good_sql):
            result = nl_to_sql("Сколько клиентов?")
        assert result == good_sql

    def test_retry_after_invalid_sql(self):
        good_sql = "SELECT SUM(PNL_SUM) FROM client_product"
        with with_llm_seq("DELETE FROM client_product", good_sql):
            result = nl_to_sql("Суммарный доход?")
        assert result == good_sql

    def test_fallback_to_no_sql_after_all_retries(self):
        with with_llm_seq("мусор1", "мусор2", "мусор3"):
            result = nl_to_sql("Что-то непонятное")
        assert result == "NO_SQL"

    def test_no_retry_needed_on_first_success(self):
        good_sql = "SELECT AVG(DEP_SUM) FROM client_product"
        call_count = []

        def fake_llm(sys_p, usr_p, temperature=0.1):
            call_count.append(1)
            return good_sql

        with patch("nl2sql.agent.call_llm", side_effect=fake_llm):
            result = nl_to_sql("Средний депозит?")

        assert result == good_sql
        assert len(call_count) == 1
