"""Minimal users service. Synthetic fixture для harness benchmark."""

from dataclasses import dataclass


@dataclass
class User:
    email: str
    name: str


class UsersService:
    def __init__(self) -> None:
        self._users: dict[str, User] = {}

    def add_user(self, email: str, name: str) -> dict:
        # BUG (T02): silently overwrites existing user with same email.
        # Expected: detect duplicate, return error or raise ValueError.
        user = User(email=email, name=name)
        self._users[email] = user
        return {"status": "ok", "email": email}

    def get_user(self, email: str) -> User | None:
        return self._users.get(email)

    def list_users(self) -> list[User]:
        return list(self._users.values())

    def delete_user(self, email: str) -> bool:
        if email in self._users:
            del self._users[email]
            return True
        return False
