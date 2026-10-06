import pytest
from werkzeug.security import check_password_hash

from familyapp import create_app
from familyapp.cli import bootstrap_parents
from familyapp.domain import DomainError
from familyapp.persistence import get_db


def test_bootstrap_creates_equal_parents_without_overwriting(database_path):
    app = create_app({"TESTING": True, "DATABASE": str(database_path)})
    with app.app_context():
        family_id = bootstrap_parents("vlad-long-password", "katya-long-password")
        rows = get_db().execute("SELECT u.*, m.role, m.family_id FROM users u JOIN members m ON m.user_id = u.id ORDER BY u.id").fetchall()
        assert [(r["name"], r["login"], r["role"], r["family_id"]) for r in rows] == [
            ("Влад", "vlad", "parent", family_id), ("Катя", "katya", "parent", family_id)]
        assert check_password_hash(rows[0]["password_hash"], "vlad-long-password")
        assert check_password_hash(rows[1]["password_hash"], "katya-long-password")
        with pytest.raises(DomainError):
            bootstrap_parents("another-password", "another-password")
        assert get_db().execute("SELECT count(*) FROM families").fetchone()[0] == 1
        assert get_db().execute("SELECT password_hash FROM users WHERE login = 'vlad'").fetchone()[0] == rows[0]["password_hash"]


def test_bootstrap_invalid_second_password_creates_nothing(database_path):
    app = create_app({"TESTING": True, "DATABASE": str(database_path)})
    with app.app_context():
        with pytest.raises(DomainError):
            bootstrap_parents("vlad-long-password", "short")
        assert get_db().execute("SELECT count(*) FROM users").fetchone()[0] == 0
        assert get_db().execute("SELECT count(*) FROM families").fetchone()[0] == 0
