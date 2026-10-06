from datetime import date
import sqlite3

from conftest import authorize, login_as, make_app
from test_accounts import create_member, create_restriction


def register_user(client, login="second"):
    response = client.post("/api/auth/register", json={"name": login, "login": login, "password": "secret-123"})
    assert response.status_code == 201, response.get_json()
    authorize(client, response.get_json()["token"])
    return client


def test_two_users_join_same_family_as_equal_parents(client):
    other = register_user(client.application.test_client())
    invite = client.post("/api/invitations", json={"role": "parent"}).get_json()
    response = other.post("/api/invitations/accept", json={"code": invite["code"]})
    assert response.status_code == 200
    assert response.get_json()["member"]["role"] == "parent"
    assert response.get_json()["family_id"] == client.get("/api/me").get_json()["family_id"]
    assert other.post("/api/children", json={"name": "Child"}).status_code == 201
    assert len(client.get("/api/children").get_json()["children"]) == 1
    assert len(other.get("/api/members").get_json()["members"]) == 3


def test_invitation_is_single_use_and_only_hash_is_stored(client, database_path):
    invite = client.post("/api/invitations", json={"role": "parent"}).get_json()
    other = register_user(client.application.test_client())
    assert other.post("/api/invitations/accept", json={"code": invite["code"]}).status_code == 200
    third = register_user(client.application.test_client(), "third")
    assert third.post("/api/invitations/accept", json={"code": invite["code"]}).status_code == 400
    assert third.get("/api/me").get_json()["families"] == []
    with sqlite3.connect(database_path) as db:
        assert db.execute("SELECT token_hash FROM invitations").fetchone()[0] != invite["code"]


def test_expired_or_unknown_invitation_grants_no_access(client, database_path):
    invite = client.post("/api/invitations", json={"role": "parent"}).get_json()
    with sqlite3.connect(database_path) as db:
        db.execute("UPDATE invitations SET expires_at = '2000-01-01'")
    other = register_user(client.application.test_client())
    for code in (invite["code"], "unknown"):
        assert other.post("/api/invitations/accept", json={"code": code}).status_code == 400
    assert other.get("/api/me").get_json()["families"] == []


def test_child_invitation_cannot_upgrade_role_and_preserves_member(client):
    child = create_member(client, "Child", "child")
    restriction = create_restriction(client, child["id"])
    invite = client.post("/api/invitations", json={"role": "parent", "member_id": child["id"]}).get_json()
    assert invite["role"] == "child"
    other = register_user(client.application.test_client())
    result = other.post("/api/invitations/accept", json={"code": invite["code"], "role": "parent"}).get_json()
    assert result["member"]["id"] == child["id"]
    assert result["member"]["role"] == "child"
    assert other.get("/api/restrictions").get_json()["restrictions"][0]["id"] == restriction["id"]
    assert other.post("/api/invitations", json={"role": "parent"}).status_code == 403


def test_competing_invitations_cannot_replace_linked_user(client):
    child = create_member(client, "Child", "child")
    codes = [client.post("/api/invitations", json={"member_id": child["id"]}).get_json()["code"] for _ in range(2)]
    other = register_user(client.application.test_client())
    third = register_user(client.application.test_client(), "third")
    assert other.post("/api/invitations/accept", json={"code": codes[0]}).status_code == 200
    assert third.post("/api/invitations/accept", json={"code": codes[1]}).status_code == 400
    assert third.get("/api/me").get_json()["families"] == []


def test_family_data_is_isolated_even_with_known_ids(client):
    child = create_member(client, "Private child", "child")
    restriction = create_restriction(client, child["id"])
    kind = client.post("/api/restriction-types", json={"name": "Private type", "color": "#000000"}).get_json()["restriction_type"]
    other = register_user(client.application.test_client())
    assert other.post("/api/families", json={"name": "Other family"}).status_code == 201
    for path, key in (("/api/members", "members"), ("/api/children", "children"), ("/api/restrictions", "restrictions"), ("/api/restriction-types", "restriction_types")):
        items = other.get(path).get_json()[key]
        assert len(items) == (1 if key == "members" else 0)
    today = date.today().isoformat()
    assert other.get(f"/api/restrictions/range?start_date={today}&end_date={today}").get_json()["restrictions"] == []
    assert other.get("/api/restrictions/today").get_json()["restrictions"] == []
    assert other.get(f"/api/restrictions?child_id={child['id']}").get_json()["restrictions"] == []
    for path, payload in (
        (f"/api/members/{child['id']}", {"name": "Changed"}),
        (f"/api/children/{child['id']}", {"name": "Changed"}),
        (f"/api/restrictions/{restriction['id']}/cancel", {}),
        (f"/api/restrictions/{restriction['id']}/extend", {"new_end_date": "2099-01-01"}),
        (f"/api/restriction-types/{kind['id']}/archive", {}),
        ("/api/invitations", {"member_id": child["id"]}),
        ("/api/restrictions", {"child_id": child["id"], "start_date": today, "end_date": today, "custom_type_name": "X"}),
    ):
        assert other.post(path, json=payload).status_code == 400, path
    own_child = create_member(other, "Own child", "child")
    assert other.post("/api/restrictions", json={"child_id": own_child["id"], "restriction_type_id": kind["id"], "start_date": today, "end_date": today}).status_code == 400
    family = client.get("/api/me").get_json()["family_id"]
    assert other.post(f"/api/families/{family}/select").status_code == 403
    assert client.get("/api/children").get_json()["children"][0]["name"] == "Private child"
    assert client.get("/api/restrictions").get_json()["restrictions"][0]["status"] == "active"


def test_multiple_families_switch_and_restore_without_shared_data(client, database_path):
    first = client.get("/api/me").get_json()["family_id"]
    create_member(client, "First child", "child")
    second = client.post("/api/families", json={"name": "Second"}).get_json()["family_id"]
    assert second != first
    assert client.get("/api/children").get_json()["children"] == []
    assert client.post(f"/api/families/{first}/select").status_code == 200
    assert len(client.get("/api/children").get_json()["children"]) == 1
    restarted = make_app(database_path).test_client()
    restarted.environ_base.update(client.environ_base)
    assert restarted.get("/api/me").get_json()["family_id"] == first
    login_as(restarted, "mama", "secret-123")
    assert restarted.get("/api/me").get_json()["member"] is None
    assert len(restarted.get("/api/me").get_json()["families"]) == 2


def test_existing_credentials_migrate_and_public_registration_cannot_claim_family(database_path):
    from werkzeug.security import generate_password_hash
    with sqlite3.connect(database_path) as db:
        db.execute("CREATE TABLE members(id INTEGER PRIMARY KEY, name TEXT, icon TEXT, role TEXT, login TEXT UNIQUE, password_hash TEXT, created_by_member_id INTEGER, created_at TEXT, updated_at TEXT)")
        db.execute("INSERT INTO members VALUES (1, 'Parent', 'star', 'parent', 'legacy', ?, NULL, 'x', 'x')", (generate_password_hash("secret-123"),))
    app = make_app(database_path)
    old = login_as(app.test_client(), "legacy", "secret-123")
    assert old.get("/api/me").get_json()["member"]["id"] == 1
    new = register_user(app.test_client())
    assert new.get("/api/me").get_json()["families"] == []
    assert new.get("/api/members").status_code == 403
    make_app(database_path)
    assert old.get("/api/me").status_code == 200
