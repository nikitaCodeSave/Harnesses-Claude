"""Unit tests for nl2sql.validator."""

import pytest
from nl2sql.validator import check_domain_rules, validate_sql

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
VALID_SELECT = (
    "SELECT COUNT(DISTINCT INN) AS cnt "
    "FROM client_product "
    "WHERE MONTH_DT = (SELECT MAX(MONTH_DT) FROM client_product "
    "WHERE MONTH_DT = LAST_DAY(MONTH_DT)) AND ACT_1M = 1"
)


# ---------------------------------------------------------------------------
# validate_sql — passing cases
# ---------------------------------------------------------------------------
class TestValidateSQLPass:
    def test_no_sql_always_valid(self):
        ok, errors = validate_sql("NO_SQL")
        assert ok
        assert errors == []

    def test_simple_select(self):
        ok, errors = validate_sql("SELECT * FROM client_product")
        assert ok

    def test_complex_select_with_subquery(self):
        ok, errors = validate_sql(VALID_SELECT)
        assert ok

    def test_select_with_avg_balance(self):
        # AVG on balance column over a multi-month range — correct usage
        sql = (
            "SELECT AVG(CA_LCY_RUB_SUM) AS avg_ca "
            "FROM client_product "
            "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01'"
        )
        ok, errors = validate_sql(sql)
        assert ok, errors

    def test_select_with_sum_pnl(self):
        # SUM on a flow column — always correct
        sql = (
            "SELECT SUM(PNL_SUM) AS total_pnl "
            "FROM client_product "
            "WHERE MONTH_DT >= DATE'2024-01-01'"
        )
        ok, errors = validate_sql(sql)
        assert ok, errors

    def test_fetch_first_syntax(self):
        sql = (
            "SELECT INN, SUM(PNL_SUM) AS pnl FROM client_product "
            "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01' "
            "GROUP BY INN ORDER BY pnl DESC FETCH FIRST 10 ROWS ONLY"
        )
        ok, errors = validate_sql(sql)
        assert ok, errors

    def test_multiline_select(self):
        sql = (
            "SELECT SEG,\n"
            "       SUM(PL_CA) AS pnl_ca,\n"
            "       SUM(PL_DEP) AS pnl_dep,\n"
            "       SUM(PNL_SUM) AS total_pnl\n"
            "FROM client_product\n"
            "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2024-04-01'\n"
            "GROUP BY SEG"
        )
        ok, errors = validate_sql(sql)
        assert ok, errors

    def test_create_dt_filter(self):
        sql = (
            "SELECT COUNT(DISTINCT INN) AS new_clients "
            "FROM client_product "
            "WHERE TRUNC(CREATE_DT, 'MM') = TRUNC(DATE'2024-01-01', 'MM')"
        )
        ok, errors = validate_sql(sql)
        assert ok, errors


# ---------------------------------------------------------------------------
# validate_sql — failure cases
# ---------------------------------------------------------------------------
class TestValidateSQLFail:
    def test_rejects_update(self):
        ok, errors = validate_sql("UPDATE client_product SET SEG = 'X'")
        assert not ok
        assert any("SELECT" in e for e in errors)

    def test_rejects_delete(self):
        ok, errors = validate_sql("DELETE FROM client_product WHERE INN = 1")
        assert not ok

    def test_rejects_drop(self):
        sql = "SELECT 1 FROM dual; DROP TABLE client_product"
        ok, errors = validate_sql(sql)
        assert not ok
        assert any("DROP" in e for e in errors)

    def test_rejects_insert(self):
        ok, errors = validate_sql("INSERT INTO client_product VALUES (1)")
        assert not ok

    def test_rejects_missing_table(self):
        ok, errors = validate_sql("SELECT * FROM orders WHERE id = 1")
        assert not ok
        assert any("client_product" in e.lower() for e in errors)

    def test_rejects_unbalanced_parens_open(self):
        ok, errors = validate_sql("SELECT COUNT(INN FROM client_product")
        assert not ok
        assert any("parenthes" in e.lower() for e in errors)

    def test_rejects_unbalanced_parens_close(self):
        ok, errors = validate_sql("SELECT COUNT(INN)) FROM client_product")
        assert not ok

    def test_rejects_sum_on_balance_with_range(self):
        # SUM(CA_LCY_SUM) with a multi-month range filter — domain rule violation
        sql = (
            "SELECT SUM(CA_LCY_SUM) AS wrong_total "
            "FROM client_product "
            "WHERE MONTH_DT >= DATE'2024-01-01' AND MONTH_DT < DATE'2025-01-01'"
        )
        ok, errors = validate_sql(sql)
        assert not ok
        assert any("AVG" in e for e in errors)

    def test_rejects_sum_on_dep_with_add_months(self):
        sql = (
            "SELECT SUM(DEP_SUM) AS wrong "
            "FROM client_product "
            "WHERE MONTH_DT >= ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -6)"
        )
        ok, errors = validate_sql(sql)
        assert not ok
        assert any("DEP_SUM" in e for e in errors)


# ---------------------------------------------------------------------------
# check_domain_rules — warnings
# ---------------------------------------------------------------------------
class TestDomainRules:
    def test_warns_on_limit(self):
        sql = "SELECT * FROM client_product LIMIT 10"
        warnings = check_domain_rules(sql)
        assert any("LIMIT" in w for w in warnings)

    def test_no_warning_fetch_first(self):
        sql = (
            "SELECT INN FROM client_product "
            "ORDER BY PNL_SUM DESC FETCH FIRST 10 ROWS ONLY"
        )
        warnings = check_domain_rules(sql)
        assert not any("LIMIT" in w for w in warnings)

    def test_no_warning_clean_query(self):
        ok_sql = (
            "SELECT SEG, AVG(CA_LCY_RUB_SUM) AS avg_ca "
            "FROM client_product WHERE MONTH_DT >= DATE'2024-01-01' "
            "GROUP BY SEG"
        )
        assert check_domain_rules(ok_sql) == []
