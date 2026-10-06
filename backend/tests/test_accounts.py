from __future__ import annotations

import sqlite3
from datetime import date

from conftest import (
    PARENT_LOGIN,
    PARENT_PASSWORD,
    authorize,
    login_as,
    make_app,
    setup_parent,
)


def create_member(client, name, role, login=None, password=None, icon="star"):
    payload = {"name": name, "role": role, "icon": icon}
    response = client.post("/api/members", json=payload)
    assert response.status_code == 201, response.get_json()
    member = response.get_json()["member"]
    if login:
        invitation = client.post("/api/invitations", json={"member_id": member["id"]}).get_json()
        other = client.application.test_client()
        registered = other.post("/api/auth/register", json={"name": name, "login": login, "password": password})
        assert registered.status_code == 201, registered.get_json()
        authorize(other, registered.get_json()["token"])
        assert other.post("/api/invitations/accept", json={"code": invitation["code"]}).status_code == 200
        member = other.get("/api/me").get_json()["member"]
    return member


def create_restriction(client, child_id):
    today = date.today().isoformat()
    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child_id,
            "start_date": today,
            "end_date": today,
            "custom_type_name": "No cartoons",
            "reason": "",
        },
    )
    assert response.status_code == 201, response.get_json()
    return response.get_json()["restriction"]


def test_registration_is_independent_of_family(anonymous_client):
    response = anonymous_client.post("/api/auth/register", json={"name": "Mama", "login": "mama", "password": "secret-123"})
    assert response.status_code == 201
    data = response.get_json()
    assert data["member"] is None
    assert data["families"] == []
    assert "password_hash" not in data["user"]
    authorize(anonymous_client, data["token"])
    assert anonymous_client.get("/api/children").status_code == 403
    assert anonymous_client.post("/api/auth/setup", json={}).status_code == 404


def test_api_requires_authentication(anonymous_client):
    assert anonymous_client.get("/health").status_code == 200
    response = anonymous_client.get("/api/children")
    assert response.status_code == 401

    authorize(anonymous_client, "not-a-real-token")
    assert anonymous_client.get("/api/children").status_code == 401


def test_login_rejects_wrong_password(client, database_path):
    other = make_app(database_path).test_client()
    response = other.post(
        "/api/auth/login",
        json={"login": PARENT_LOGIN, "password": "wrong-password"},
    )
    assert response.status_code == 401

    unknown = other.post("/api/auth/login", json={"login": "nobody", "password": "x"})
    assert unknown.status_code == 401


def test_login_is_case_insensitive(client, database_path):
    other = make_app(database_path).test_client()
    login_as(other, PARENT_LOGIN.upper(), PARENT_PASSWORD)
    assert other.get("/api/me").status_code == 200


def test_logout_revokes_token(client):
    assert client.post("/api/auth/logout").status_code == 200
    assert client.get("/api/me").status_code == 401


def test_parent_creates_members_with_and_without_accounts(client):
    create_member(client, "Papa", "parent", login="papa", password="papa-pass")
    create_member(client, "Masha", "child", login="masha", password="masha-pass")
    create_member(client, "Baby", "child")

    members = client.get("/api/members").get_json()["members"]
    by_name = {member["name"]: member for member in members}
    assert by_name["Papa"]["has_account"] is True
    assert by_name["Baby"]["has_account"] is False
    assert by_name["Baby"]["login"] is None
    assert [member["role"] for member in members] == ["parent", "parent", "child", "child"]

    children = client.get("/api/children").get_json()["children"]
    assert {child["name"] for child in children} == {"Masha", "Baby"}


def test_member_validation(client):
    response = client.post("/api/members", json={"name": "X", "role": "guest"})
    assert response.status_code == 400

    response = client.post(
        "/api/members",
        json={"name": "X", "role": "child", "login": "x-login"},
    )
    assert response.status_code == 400

    response = client.post(
        "/api/members",
        json={"name": "X", "role": "child", "login": "x", "password": "secret-123"},
    )
    assert response.status_code == 400

    response = client.post(
        "/api/members",
        json={"name": "X", "role": "child", "login": "xenia", "password": "123"},
    )
    assert response.status_code == 400


def test_login_must_be_unique(client):
    create_member(client, "Masha", "child", login="masha", password="masha-pass")
    other = client.application.test_client()
    response = other.post(
        "/api/auth/register",
        json={"name": "Other", "login": "MASHA", "password": "secret-123"},
    )
    assert response.status_code == 400
    assert response.get_json()["error"] == "login is already taken"
    names = [member["name"] for member in client.get("/api/members").get_json()["members"]]
    assert "Other" not in names


def test_child_cannot_manage_but_can_read(client, database_path):
    masha = create_member(client, "Masha", "child", login="masha", password="masha-pass")
    child = login_as(make_app(database_path).test_client(), "masha", "masha-pass")

    assert child.get("/api/children").status_code == 200
    assert child.post("/api/members", json={"name": "X", "role": "child"}).status_code == 403
    assert child.post("/api/children", json={"name": "X"}).status_code == 403
    assert child.post(
        "/api/restriction-types",
        json={"name": "TV", "color": "#000000"},
    ).status_code == 403

    restriction = create_restriction(client, masha["id"])
    assert child.post(f"/api/restrictions/{restriction['id']}/cancel", json={}).status_code == 403


def test_child_sees_only_own_restrictions(client, database_path):
    masha = create_member(client, "Masha", "child", login="masha", password="masha-pass")
    petya = create_member(client, "Petya", "child")
    create_restriction(client, masha["id"])
    create_restriction(client, petya["id"])

    child = login_as(make_app(database_path).test_client(), "masha", "masha-pass")
    today = date.today().isoformat()
    for path in (
        "/api/restrictions",
        f"/api/restrictions?child_id={petya['id']}",
        "/api/restrictions/today",
        f"/api/restrictions/range?start_date={today}&end_date={today}",
    ):
        restrictions = child.get(path).get_json()["restrictions"]
        assert [item["child_id"] for item in restrictions] == [masha["id"]], path

    assert len(client.get("/api/restrictions").get_json()["restrictions"]) == 2


def test_restriction_audit_uses_current_parent(client, database_path):
    papa = create_member(client, "Papa", "parent", login="papa", password="papa-pass")
    child = create_member(client, "Masha", "child")
    restriction = create_restriction(client, child["id"])

    papa_client = login_as(make_app(database_path).test_client(), "papa", "papa-pass")
    papa_client.post(f"/api/restrictions/{restriction['id']}/cancel", json={})

    db = sqlite3.connect(database_path)
    row = db.execute(
        "SELECT created_by_admin_id, updated_by_admin_id FROM restrictions WHERE id = ?",
        (restriction["id"],),
    ).fetchone()
    db.close()
    assert row[1] == papa["id"]
    assert row[0] != papa["id"]


def test_restriction_requires_child_member(client):
    papa = create_member(client, "Papa", "parent")
    today = date.today().isoformat()
    response = client.post(
        "/api/restrictions",
        json={
            "child_id": papa["id"],
            "start_date": today,
            "end_date": today,
            "custom_type_name": "No cartoons",
        },
    )
    assert response.status_code == 400


def test_changing_password_signs_out_other_sessions(client, database_path):
    masha = create_member(client, "Masha", "child", login="masha", password="masha-pass")
    phone = login_as(make_app(database_path).test_client(), "masha", "masha-pass")
    tablet = login_as(make_app(database_path).test_client(), "masha", "masha-pass")

    response = phone.post(
        f"/api/members/{masha['id']}/credentials",
        json={"login": "masha", "password": "new-pass-1"},
    )
    assert response.status_code == 200
    assert phone.get("/api/me").status_code == 200
    assert tablet.get("/api/me").status_code == 401


def test_child_cannot_change_other_credentials(client, database_path):
    create_member(client, "Masha", "child", login="masha", password="masha-pass")
    me = client.get("/api/me").get_json()["member"]
    child = login_as(make_app(database_path).test_client(), "masha", "masha-pass")

    response = child.post(
        f"/api/members/{me['id']}/credentials",
        json={"login": "hacked", "password": "hacked-pass"},
    )
    assert response.status_code == 403


def test_parent_cannot_change_another_users_password(client, database_path):
    other = create_member(client, "Papa", "parent", login="papa", password="papa-pass")
    response = client.post(f"/api/members/{other['id']}/credentials", json={"login": "papa", "password": "changed-password"})
    assert response.status_code == 403


def test_legacy_database_is_migrated(database_path):
    db = sqlite3.connect(database_path)
    db.executescript(
        """
        CREATE TABLE parent_admins (id INTEGER PRIMARY KEY, name TEXT, created_at TEXT);
        CREATE TABLE children (
            id INTEGER PRIMARY KEY, name TEXT, icon TEXT,
            created_by_admin_id INTEGER, created_at TEXT
        );
        CREATE TABLE restrictions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            child_id INTEGER NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            reason TEXT NOT NULL,
            status TEXT NOT NULL,
            created_by_admin_id INTEGER NOT NULL,
            updated_by_admin_id INTEGER NOT NULL,
            cancelled_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        INSERT INTO parent_admins VALUES (1, 'Parent Admin', '2026-01-01T00:00:00');
        INSERT INTO children VALUES (1, 'Misha', 'dragon', 1, '2026-01-01T00:00:00');
        INSERT INTO children VALUES (2, 'Anya', 'pet', 1, '2026-01-01T00:00:00');
        INSERT INTO restrictions (
            child_id, start_date, end_date, reason, status,
            created_by_admin_id, updated_by_admin_id, created_at, updated_at
        ) VALUES (2, '2026-01-01', '2099-01-01', 'Old', 'active', 1, 1, 'x', 'x');
        """
    )
    db.close()

    client = make_app(database_path).test_client()
    token = setup_parent(client, name="Mama")
    authorize(client, token)
    assert len(client.get("/api/members").get_json()["members"]) == 1
    assert client.get("/api/children").get_json()["children"] == []
    assert client.get("/api/restrictions").get_json()["restrictions"] == []
    db = sqlite3.connect(database_path)
    assert db.execute("SELECT name FROM members WHERE id = 1").fetchone()[0] == "Misha"
    assert db.execute("SELECT COUNT(*) FROM restrictions").fetchone()[0] == 1
    legacy_family = db.execute("SELECT family_id FROM members WHERE id = 1").fetchone()[0]
    assert legacy_family != client.get("/api/me").get_json()["family_id"]
    db.close()
