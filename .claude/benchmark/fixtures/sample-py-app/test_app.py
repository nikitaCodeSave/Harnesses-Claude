"""Baseline tests для sample-py-app — все должны pass перед Claude changes."""

from app import UsersService


def test_add_user_basic():
    svc = UsersService()
    result = svc.add_user("alice@example.com", "Alice")
    assert result["status"] == "ok"
    assert result["email"] == "alice@example.com"


def test_get_user_existing():
    svc = UsersService()
    svc.add_user("alice@example.com", "Alice")
    user = svc.get_user("alice@example.com")
    assert user is not None
    assert user.name == "Alice"


def test_get_user_missing():
    svc = UsersService()
    assert svc.get_user("nobody@example.com") is None


def test_list_users_empty():
    svc = UsersService()
    assert svc.list_users() == []


def test_delete_user_existing():
    svc = UsersService()
    svc.add_user("alice@example.com", "Alice")
    assert svc.delete_user("alice@example.com") is True
    assert svc.get_user("alice@example.com") is None


def test_delete_user_missing():
    svc = UsersService()
    assert svc.delete_user("nobody@example.com") is False
