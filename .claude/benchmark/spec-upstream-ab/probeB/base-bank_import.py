"""Импорт дневной банковской выгрузки в биллинг."""

import sqlite3

SCHEMA = ""


def init_db(conn: sqlite3.Connection) -> None:
    raise NotImplementedError


def import_file(conn: sqlite3.Connection, path: str) -> int:
    """Разносит выгрузку. Возвращает число применённых строк."""
    raise NotImplementedError
