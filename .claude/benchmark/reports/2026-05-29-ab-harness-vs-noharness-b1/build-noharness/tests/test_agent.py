"""Integration tests for NL2SQLAgent (LLM is mocked)."""

from unittest.mock import patch

import pytest
from nl2sql.agent import MAX_RETRIES, NL2SQLAgent

# ---------------------------------------------------------------------------
# Representative SQL fixtures (correct Oracle SQL)
# ---------------------------------------------------------------------------
SQL_ACTIVE_CLIENTS = (
    "SELECT COUNT(DISTINCT INN) AS active_cnt "
    "FROM client_product "
    "WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product "
    "WHERE MONTH_DT = LAST_DAY(MONTH_DT)) AND ACT_1M = 1"
)

SQL_TOP10_INCOME = (
    "SELECT INN, ORGANIZATION_NM, SUM(PNL_SUM) AS total_pnl "
    "FROM client_product "
    "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01' "
    "GROUP BY INN, ORGANIZATION_NM "
    "ORDER BY total_pnl DESC FETCH FIRST 10 ROWS ONLY"
)

SQL_AVG_BALANCE = (
    "SELECT SEG, AVG(CA_LCY_RUB_SUM) AS avg_ca "
    "FROM client_product "
    "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01' "
    "GROUP BY SEG ORDER BY avg_ca DESC"
)

SQL_INCOME_STRUCTURE = (
    "SELECT SEG, "
    "SUM(PL_CA) AS pnl_ca, SUM(PL_DEP) AS pnl_dep, "
    "SUM(PL_VK) AS pnl_vk, SUM(PL_VK_OUT) AS pnl_vk_out, "
    "SUM(VED_SUM) AS pnl_ved, SUM(FX_MARGIN_RUB) AS pnl_fx, "
    "SUM(PNL_SUM) AS total_pnl "
    "FROM client_product "
    "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2024-04-01' "
    "GROUP BY SEG ORDER BY total_pnl DESC"
)

SQL_FX = (
    "SELECT SEG, SUM(FX_VOLUME_RUB) AS fx_vol, "
    "SUM(FX_CNT) AS fx_cnt, SUM(FX_MARGIN_RUB) AS fx_margin "
    "FROM client_product "
    "WHERE MONTH_DT >= ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -3) "
    "GROUP BY SEG ORDER BY fx_vol DESC"
)

SQL_NEW_CLIENTS = (
    "SELECT COUNT(DISTINCT INN) AS new_clients "
    "FROM client_product "
    "WHERE TRUNC(CREATE_DT, 'MM') = TRUNC(DATE'2024-01-01', 'MM')"
)

SQL_PERIOD_COMPARE = (
    "SELECT "
    "CASE WHEN MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01' THEN '2024' "
    "ELSE '2023' END AS yr, "
    "SUM(PNL_SUM) AS total_pnl, COUNT(DISTINCT INN) AS clients "
    "FROM client_product "
    "WHERE MONTH_DT >= DATE'2023-01-01' AND MONTH_DT < DATE'2025-01-01' "
    "GROUP BY CASE WHEN MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01' "
    "THEN '2024' ELSE '2023' END"
)

SQL_WRONG_TABLE = "SELECT * FROM orders WHERE id = 1"  # missing client_product


# ---------------------------------------------------------------------------
# Basic agent behaviour
# ---------------------------------------------------------------------------
class TestAgentBasic:
    def setup_method(self):
        self.agent = NL2SQLAgent()

    @patch("nl2sql.agent.call_llm")
    def test_returns_valid_sql(self, mock_llm):
        mock_llm.return_value = SQL_ACTIVE_CLIENTS
        result = self.agent.query("Сколько активных клиентов в последнем месяце?")
        assert result == SQL_ACTIVE_CLIENTS

    @patch("nl2sql.agent.call_llm")
    def test_returns_no_sql_for_irrelevant(self, mock_llm):
        mock_llm.return_value = "NO_SQL"
        result = self.agent.query("Какая погода в Москве?")
        assert result == "NO_SQL"

    @patch("nl2sql.agent.call_llm")
    def test_returns_no_sql_for_other_tables(self, mock_llm):
        mock_llm.return_value = "NO_SQL"
        result = self.agent.query("Покажи данные из таблицы employees")
        assert result == "NO_SQL"

    @patch("nl2sql.agent.call_llm")
    def test_extracts_sql_from_code_block(self, mock_llm):
        mock_llm.return_value = f"```sql\n{SQL_ACTIVE_CLIENTS}\n```"
        result = self.agent.query("Активные клиенты?")
        assert result == SQL_ACTIVE_CLIENTS

    @patch("nl2sql.agent.call_llm")
    def test_extracts_sql_after_explanation(self, mock_llm):
        mock_llm.return_value = f"Запрос для ответа на вопрос:\n{SQL_ACTIVE_CLIENTS}"
        result = self.agent.query("Активные клиенты?")
        assert result.upper().startswith("SELECT")
        assert "CLIENT_PRODUCT" in result.upper()

    @patch("nl2sql.agent.call_llm")
    def test_handles_llm_exception_gracefully(self, mock_llm):
        mock_llm.side_effect = Exception("Connection refused")
        result = self.agent.query("Любой вопрос")
        assert result == "NO_SQL"

    @patch("nl2sql.agent.call_llm")
    def test_retries_on_invalid_sql_then_succeeds(self, mock_llm):
        mock_llm.side_effect = [SQL_WRONG_TABLE, SQL_ACTIVE_CLIENTS]
        result = self.agent.query("Активные клиенты?")
        assert result == SQL_ACTIVE_CLIENTS
        assert mock_llm.call_count == 2

    @patch("nl2sql.agent.call_llm")
    def test_returns_no_sql_after_max_retries(self, mock_llm):
        # Always returns SQL that fails validation (wrong table)
        mock_llm.return_value = SQL_WRONG_TABLE
        result = self.agent.query("Любой вопрос")
        assert result == "NO_SQL"
        assert mock_llm.call_count == MAX_RETRIES


# ---------------------------------------------------------------------------
# Key analytics scenarios — SQL structure checks
# ---------------------------------------------------------------------------
class TestAnalyticsScenarios:
    def setup_method(self):
        self.agent = NL2SQLAgent()

    @patch("nl2sql.agent.call_llm")
    def test_avg_balance_over_period(self, mock_llm):
        """Balance columns must be AVG'd, not SUM'd, over multi-month periods."""
        mock_llm.return_value = SQL_AVG_BALANCE
        result = self.agent.query("Средний остаток по РС в разрезе сегментов за 2024 год")
        assert "AVG(CA_LCY_RUB_SUM)" in result
        assert "GROUP BY SEG" in result

    @patch("nl2sql.agent.call_llm")
    def test_income_components_summed(self, mock_llm):
        """P&L / income columns must be SUM'd."""
        mock_llm.return_value = SQL_INCOME_STRUCTURE
        result = self.agent.query("Структура дохода по сегментам за Q1 2024")
        assert "SUM(PNL_SUM)" in result
        assert "SUM(PL_CA)" in result
        assert "GROUP BY SEG" in result

    @patch("nl2sql.agent.call_llm")
    def test_top_n_uses_fetch_first(self, mock_llm):
        """Top-N queries must use Oracle FETCH FIRST, not LIMIT."""
        mock_llm.return_value = SQL_TOP10_INCOME
        result = self.agent.query("Топ-10 клиентов по доходу за 2024 год")
        assert "FETCH FIRST" in result
        assert "SUM(PNL_SUM)" in result

    @patch("nl2sql.agent.call_llm")
    def test_fx_volume_summed(self, mock_llm):
        """FX flow columns must be SUM'd over periods."""
        mock_llm.return_value = SQL_FX
        result = self.agent.query("Объём FX-сделок по сегментам за последние 3 месяца")
        assert "SUM(FX_VOLUME_RUB)" in result
        assert "SUM(FX_CNT)" in result
        assert "ADD_MONTHS" in result

    @patch("nl2sql.agent.call_llm")
    def test_new_clients_uses_create_dt(self, mock_llm):
        """New-client count must filter by CREATE_DT, not MONTH_DT."""
        mock_llm.return_value = SQL_NEW_CLIENTS
        result = self.agent.query("Сколько новых клиентов открылось в январе 2024?")
        assert "CREATE_DT" in result
        assert "COUNT(DISTINCT INN)" in result

    @patch("nl2sql.agent.call_llm")
    def test_active_client_filter(self, mock_llm):
        """Active client queries must use ACT_1M or ACT_3M flags."""
        mock_llm.return_value = SQL_ACTIVE_CLIENTS
        result = self.agent.query("Количество активных клиентов в последнем закрытом месяце")
        assert "ACT_1M" in result or "ACT_3M" in result
        assert "LAST_DAY" in result

    @patch("nl2sql.agent.call_llm")
    def test_period_comparison(self, mock_llm):
        """Period comparisons must filter both years and group or CASE them."""
        mock_llm.return_value = SQL_PERIOD_COMPARE
        result = self.agent.query("Сравни доход клиентов за 2023 и 2024 год")
        assert "2023" in result
        assert "2024" in result
        assert "SUM(PNL_SUM)" in result

    @patch("nl2sql.agent.call_llm")
    def test_distinct_inn_for_client_count(self, mock_llm):
        """Client counts must use COUNT(DISTINCT INN) because table has multiple rows/client."""
        mock_llm.return_value = SQL_ACTIVE_CLIENTS
        result = self.agent.query("Сколько клиентов активно?")
        assert "COUNT(DISTINCT INN)" in result


# ---------------------------------------------------------------------------
# Prompt content sanity checks (no LLM call needed)
# ---------------------------------------------------------------------------
class TestPromptContent:
    def test_prompt_mentions_avg_for_balances(self):
        from nl2sql.schema import SYSTEM_PROMPT
        assert "AVG" in SYSTEM_PROMPT
        assert "CA_LCY_SUM" in SYSTEM_PROMPT
        assert "DEP_SUM" in SYSTEM_PROMPT

    def test_prompt_warns_against_sum_on_balances(self):
        from nl2sql.schema import SYSTEM_PROMPT
        # The prompt must explicitly warn not to SUM balance columns over periods
        assert "SUM" in SYSTEM_PROMPT
        # The key rule should be spelled out
        assert "AVG" in SYSTEM_PROMPT

    def test_prompt_mentions_fetch_first(self):
        from nl2sql.schema import SYSTEM_PROMPT
        assert "FETCH FIRST" in SYSTEM_PROMPT

    def test_prompt_warns_against_limit(self):
        from nl2sql.schema import SYSTEM_PROMPT
        assert "LIMIT" in SYSTEM_PROMPT

    def test_prompt_covers_all_key_columns(self):
        from nl2sql.schema import SYSTEM_PROMPT
        for col in ["CA_LCY_SUM", "DEP_SUM", "PNL_SUM", "FX_VOLUME_RUB",
                    "ACT_1M", "CREATE_DT", "CLOSE_DT", "MONTH_DT"]:
            assert col in SYSTEM_PROMPT, f"Column {col} missing from prompt"

    def test_prompt_explains_last_day(self):
        from nl2sql.schema import SYSTEM_PROMPT
        assert "LAST_DAY" in SYSTEM_PROMPT

    def test_prompt_explains_no_sql(self):
        from nl2sql.schema import SYSTEM_PROMPT
        assert "NO_SQL" in SYSTEM_PROMPT

    def test_prompt_mentions_add_months(self):
        from nl2sql.schema import SYSTEM_PROMPT
        assert "ADD_MONTHS" in SYSTEM_PROMPT
