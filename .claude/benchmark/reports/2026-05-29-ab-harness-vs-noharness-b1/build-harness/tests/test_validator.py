from nl2sql.validator import validate_sql


def ok(sql):
    valid, msg = validate_sql(sql)
    assert valid, f"Expected valid but got error: {msg!r} for SQL: {sql!r}"


def fail(sql):
    valid, msg = validate_sql(sql)
    assert not valid, f"Expected invalid but passed for SQL: {sql!r}"
    return msg


class TestValidateSQL:
    def test_no_sql_passes(self):
        ok("NO_SQL")

    def test_empty_passes(self):
        ok("")

    def test_simple_select(self):
        ok("SELECT COUNT(*) FROM client_product")

    def test_select_with_subquery(self):
        ok("SELECT * FROM (SELECT INN FROM client_product) t")

    def test_select_with_fetch_first(self):
        ok("SELECT INN, SUM(PNL_SUM) FROM client_product GROUP BY INN ORDER BY 2 DESC FETCH FIRST 10 ROWS ONLY")

    def test_select_with_case_when(self):
        ok(
            "SELECT SEG, "
            "SUM(CASE WHEN TRUNC(MONTH_DT,'MM') = DATE '2024-01-01' THEN PNL_SUM ELSE 0 END) "
            "FROM client_product GROUP BY SEG"
        )

    def test_insert_rejected(self):
        fail("INSERT INTO client_product VALUES (1, SYSDATE)")

    def test_update_rejected(self):
        fail("UPDATE client_product SET PNL_SUM = 0")

    def test_delete_rejected(self):
        fail("DELETE FROM client_product WHERE INN = 1")

    def test_drop_rejected(self):
        fail("DROP TABLE client_product")

    def test_truncate_rejected(self):
        fail("TRUNCATE TABLE client_product")

    def test_missing_from_rejected(self):
        fail("SELECT 1 + 1")

    def test_nonsense_rejected(self):
        fail("Это не SQL вообще")

    def test_error_message_on_missing_from(self):
        msg = fail("SELECT 42")
        assert msg  # non-empty error message
