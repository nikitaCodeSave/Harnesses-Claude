import pytest
from nl2sql.parser import extract_sql, _normalize


class TestExtractSQL:
    def test_plain_no_sql(self):
        assert extract_sql("NO_SQL") == "NO_SQL"

    def test_no_sql_case_insensitive(self):
        assert extract_sql("no_sql") == "NO_SQL"

    def test_no_sql_in_sentence(self):
        assert extract_sql("На этот вопрос ответить нельзя, возвращаю NO_SQL") == "NO_SQL"

    def test_markdown_sql_block(self):
        response = "```sql\nSELECT COUNT(*) FROM client_product\n```"
        assert extract_sql(response) == "SELECT COUNT(*) FROM client_product"

    def test_markdown_plain_block(self):
        response = "```\nSELECT INN FROM client_product WHERE MONTH_DT > SYSDATE\n```"
        result = extract_sql(response)
        assert result is not None
        assert result.startswith("SELECT")

    def test_markdown_no_sql_block(self):
        assert extract_sql("```\nNO_SQL\n```") == "NO_SQL"

    def test_bare_select(self):
        response = "Вот запрос:\nSELECT COUNT(DISTINCT INN) FROM client_product"
        result = extract_sql(response)
        assert result == "SELECT COUNT(DISTINCT INN) FROM client_product"

    def test_empty_response(self):
        assert extract_sql("") is None

    def test_no_sql_and_no_select(self):
        assert extract_sql("Это не про данные таблицы") is None

    def test_semicolon_stripped(self):
        result = extract_sql("SELECT * FROM client_product;")
        assert result == "SELECT * FROM client_product"

    def test_limit_replaced_by_fetch_first(self):
        result = extract_sql("SELECT * FROM client_product ORDER BY PNL_SUM DESC LIMIT 10")
        assert result is not None
        assert "FETCH FIRST 10 ROWS ONLY" in result
        assert "LIMIT" not in result

    def test_multiline_sql_preserved(self):
        sql = "SELECT\n    INN,\n    SUM(PNL_SUM)\nFROM client_product\nGROUP BY INN"
        result = extract_sql(f"```sql\n{sql}\n```")
        assert result is not None
        assert "SUM(PNL_SUM)" in result
        assert "GROUP BY INN" in result


class TestNormalize:
    def test_trailing_semicolon(self):
        assert _normalize("SELECT 1 FROM DUAL;") == "SELECT 1 FROM DUAL"

    def test_trailing_semicolon_with_space(self):
        assert _normalize("SELECT 1 FROM DUAL ; ") == "SELECT 1 FROM DUAL"

    def test_limit_to_fetch_first(self):
        sql = _normalize("SELECT * FROM t ORDER BY x LIMIT 5")
        assert "FETCH FIRST 5 ROWS ONLY" in sql
        assert "LIMIT" not in sql

    def test_no_change_when_clean(self):
        sql = "SELECT COUNT(*) FROM client_product"
        assert _normalize(sql) == sql
