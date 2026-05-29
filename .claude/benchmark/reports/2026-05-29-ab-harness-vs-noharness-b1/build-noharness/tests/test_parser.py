"""Unit tests for nl2sql.parser."""

import pytest
from nl2sql.parser import _clean_sql, _is_no_sql, extract_sql

# ---------------------------------------------------------------------------
# Helpers / constants
# ---------------------------------------------------------------------------
SIMPLE_SQL = "SELECT COUNT(DISTINCT INN) AS cnt FROM client_product WHERE ACT_1M = 1"
MULTILINE_SQL = (
    "SELECT SEG, SUM(PNL_SUM) AS pnl\n"
    "FROM client_product\n"
    "WHERE MONTH_DT >= DATE'2024-01-01'\n"
    "GROUP BY SEG"
)


# ---------------------------------------------------------------------------
# _is_no_sql
# ---------------------------------------------------------------------------
class TestIsNoSql:
    def test_exact_match(self):
        assert _is_no_sql("NO_SQL")

    def test_with_trailing_dot(self):
        assert _is_no_sql("NO_SQL.")

    def test_uppercase(self):
        assert _is_no_sql("no_sql")

    def test_short_sentence_no_sql(self):
        # Short response that mentions NO_SQL without any SELECT
        assert _is_no_sql("Ответить на этот вопрос из таблицы нельзя. NO_SQL")

    def test_not_no_sql_when_select_present(self):
        # If the response contains SELECT it should not be treated as NO_SQL
        assert not _is_no_sql(f"NO_SQL or maybe {SIMPLE_SQL}")

    def test_not_no_sql_normal_sql(self):
        assert not _is_no_sql(SIMPLE_SQL)


# ---------------------------------------------------------------------------
# extract_sql — NO_SQL responses
# ---------------------------------------------------------------------------
class TestExtractSQLNoSql:
    def test_bare_no_sql(self):
        assert extract_sql("NO_SQL") == "NO_SQL"

    def test_no_sql_with_whitespace(self):
        assert extract_sql("  NO_SQL  ") == "NO_SQL"

    def test_no_sql_in_short_sentence(self):
        assert extract_sql("Данных нет. NO_SQL") == "NO_SQL"

    def test_empty_string(self):
        assert extract_sql("") == "NO_SQL"

    def test_whitespace_only(self):
        assert extract_sql("   \n\t  ") == "NO_SQL"

    def test_none_like_empty(self):
        # Should not crash on empty-ish input
        assert extract_sql("\n\n") == "NO_SQL"


# ---------------------------------------------------------------------------
# extract_sql — SQL extraction paths
# ---------------------------------------------------------------------------
class TestExtractSQLValid:
    def test_plain_sql_returned_as_is(self):
        assert extract_sql(SIMPLE_SQL) == SIMPLE_SQL

    def test_sql_in_triple_backtick_sql_block(self):
        response = f"```sql\n{SIMPLE_SQL}\n```"
        assert extract_sql(response) == SIMPLE_SQL

    def test_sql_in_triple_backtick_plain_block(self):
        response = f"```\n{SIMPLE_SQL}\n```"
        assert extract_sql(response) == SIMPLE_SQL

    def test_sql_after_explanation(self):
        response = f"Вот запрос:\n{SIMPLE_SQL}"
        result = extract_sql(response)
        assert result.upper().startswith("SELECT")
        assert "CLIENT_PRODUCT" in result.upper()

    def test_multiline_sql(self):
        result = extract_sql(MULTILINE_SQL)
        assert "GROUP BY SEG" in result
        assert result.upper().startswith("SELECT")

    def test_multiline_sql_in_code_block(self):
        response = f"```sql\n{MULTILINE_SQL}\n```"
        result = extract_sql(response)
        assert "GROUP BY SEG" in result

    def test_strips_thinking_tokens(self):
        response = f"<think>\nLet me analyse this carefully.\n</think>\n{SIMPLE_SQL}"
        result = extract_sql(response)
        assert "<think>" not in result
        assert result.upper().startswith("SELECT")

    def test_strips_trailing_semicolon(self):
        result = extract_sql(f"{SIMPLE_SQL};")
        assert not result.endswith(";")

    def test_code_block_with_extra_text_after(self):
        response = f"```sql\n{SIMPLE_SQL}\n```\nОбъяснение: ..."
        result = extract_sql(response)
        assert result == SIMPLE_SQL

    def test_fetch_first_preserved(self):
        sql = (
            "SELECT INN, SUM(PNL_SUM) AS pnl FROM client_product "
            "GROUP BY INN ORDER BY pnl DESC FETCH FIRST 10 ROWS ONLY"
        )
        assert extract_sql(sql) == sql


# ---------------------------------------------------------------------------
# _clean_sql
# ---------------------------------------------------------------------------
class TestCleanSQL:
    def test_removes_semicolon(self):
        assert _clean_sql("SELECT 1;") == "SELECT 1"

    def test_no_change_when_clean(self):
        assert _clean_sql(SIMPLE_SQL) == SIMPLE_SQL

    def test_preserves_multiline(self):
        assert _clean_sql(MULTILINE_SQL) == MULTILINE_SQL

    def test_strips_trailing_whitespace(self):
        assert _clean_sql("SELECT 1   ") == "SELECT 1"
