from datetime import datetime, timedelta, timezone
import sqlite3

from conftest import PARENT_LOGIN, PARENT_PASSWORD, make_app


def test_login_limit_persists_across_workers_and_normalizes_login(client, database_path, monkeypatch):
    monkeypatch.setattr("familyapp.accounts.check_password_hash", lambda *_: False)
    for attempt in range(10):
        response = client.post("/api/auth/login", json={"login": " MAMA ", "password": "wrong"},
                               environ_overrides={"REMOTE_ADDR": f"192.0.2.{attempt}"})
        assert response.status_code == 401
    other = make_app(database_path).test_client()
    response = other.post("/api/auth/login", json={"login": "mama", "password": "wrong"})
    assert response.status_code == 429
    assert 1 <= int(response.headers["Retry-After"]) <= 60
    assert "error" in response.get_json()
    with sqlite3.connect(database_path) as db:
        keys = [row[0] for row in db.execute("SELECT key FROM auth_rate_limits")]
    assert all(len(key) == 64 and "mama" not in key and "192.0.2" not in key for key in keys)


def test_address_limit_cannot_be_bypassed_with_forwarded_headers(anonymous_client, monkeypatch):
    monkeypatch.setattr("familyapp.accounts.check_password_hash", lambda *_: False)
    for attempt in range(30):
        response = anonymous_client.post("/api/auth/login", json={"login": f"unknown-{attempt}", "password": "wrong"},
                                         headers={"X-Forwarded-For": f"192.0.2.{attempt}"})
        assert response.status_code == 401
    assert anonymous_client.post("/api/auth/login", json={"login": "another", "password": "wrong"}).status_code == 429
    assert anonymous_client.post("/api/auth/login", json={"login": "another", "password": "wrong"},
                                 environ_overrides={"REMOTE_ADDR": "192.0.2.100"}).status_code == 401


def test_expired_limit_allows_valid_login_without_affecting_existing_session(client, database_path, monkeypatch):
    with monkeypatch.context() as scoped:
        scoped.setattr("familyapp.accounts.check_password_hash", lambda *_: False)
        for _ in range(10):
            assert client.post("/api/auth/login", json={"login": PARENT_LOGIN, "password": "wrong"}).status_code == 401
    assert client.post("/api/auth/login", json={"login": PARENT_LOGIN, "password": PARENT_PASSWORD}).status_code == 429
    assert client.get("/api/me").status_code == 200
    expired = (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()
    with sqlite3.connect(database_path) as db:
        db.execute("UPDATE auth_rate_limits SET resets_at = ?", (expired,))
    assert client.post("/api/auth/login", json={"login": PARENT_LOGIN, "password": PARENT_PASSWORD}).status_code == 200


def test_unknown_login_still_checks_a_password_hash(anonymous_client, monkeypatch):
    checked = []
    monkeypatch.setattr("familyapp.accounts.check_password_hash", lambda hashed, password: checked.append(hashed) or False)
    assert anonymous_client.post("/api/auth/login", json={"login": "unknown", "password": "wrong"}).status_code == 401
    assert len(checked) == 1
    assert checked[0].startswith("scrypt:")


def test_registration_limits_are_separate_from_login(anonymous_client):
    for _ in range(3):
        assert anonymous_client.post("/api/auth/register", json={"name": "", "login": "new-user", "password": "secret-123"}).status_code == 400
    assert anonymous_client.post("/api/auth/register", json={"name": "New", "login": "NEW-USER", "password": "secret-123"}).status_code == 429
    assert anonymous_client.post("/api/auth/login", json={"login": "new-user", "password": "wrong"}).status_code == 401
