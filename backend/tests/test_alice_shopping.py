from test_alice import alice_client, exchange, get_code, voice
from familyapp.persistence import get_db

SCOPES = "restrictions:read&shopping:read&shopping:write"


def token(client, scope=SCOPES):
    result = exchange(client, code=get_code(client, scope=scope))
    assert result.status_code == 200
    return result.get_json()


def items(client):
    return client.get("/api/shopping").get_json()["items"]


def test_read_add_and_duplicate_are_shared_and_one_shot(alice_client):
    access = token(alice_client)["access_token"]
    empty = voice(alice_client, access, "что нужно купить")
    assert empty["response"] == {"text": "Список покупок пуст.", "end_session": True}
    added = voice(alice_client, access, "Добавь в список покупок Молоко 3,2%")
    assert added["response"]["end_session"] is True
    assert items(alice_client)[0]["name"] == "Молоко 3,2%"
    voice(alice_client, access, "запиши молоко 3,2% в список покупок")
    assert len(items(alice_client)) == 1
    assert items(alice_client)[0]["urgency"] == "week"
    read = voice(alice_client, access, "прочитай список покупок")
    assert "Молоко 3,2%" in read["response"]["text"]
    assert read["response"]["end_session"] is True
    alice_client.post("/api/shopping", json={"name": "соль", "urgency": "background", "category": "Кухня"})
    voice(alice_client, access, "добавь в список соль")
    salt = next(item for item in items(alice_client) if item["name"] == "соль")
    assert salt["urgency"] == "background"
    assert salt["category"] == "Кухня"


def test_old_grant_has_no_shopping_access_even_after_refresh(alice_client):
    original = token(alice_client, "restrictions:read")
    denied = voice(alice_client, original["access_token"], "добавь в список молоко")
    assert "переподключите" in denied["response"]["text"]
    assert items(alice_client) == []
    refreshed = exchange(alice_client, grant_type="refresh_token", refresh_token=original["refresh_token"])
    assert refreshed.get_json()["scope"] == "restrictions:read"
    escalated = exchange(alice_client, grant_type="refresh_token", refresh_token=refreshed.get_json()["refresh_token"], scope=SCOPES)
    assert escalated.status_code == 400


def test_read_permission_cannot_add_and_write_cannot_read(alice_client):
    read = token(alice_client, "shopping:read")["access_token"]
    assert "переподключите" in voice(alice_client, read, "добавь в список хлеб")["response"]["text"]
    write = token(alice_client, "shopping:write")["access_token"]
    voice(alice_client, write, "добавь в список хлеб")
    assert "переподключите" in voice(alice_client, write, "список покупок")["response"]["text"]
    assert "переподключите" in voice(alice_client, read, "какие ограничения у ребят")["response"]["text"]


def test_clarification_limits_and_unsupported_purchase(alice_client):
    access = token(alice_client)["access_token"]
    ask = voice(alice_client, access, "добавь в список покупок")
    assert ask["response"]["end_session"] is False
    cancel = voice(alice_client, access, "не надо", state=ask["session_state"])
    assert cancel["response"]["end_session"] is True
    assert items(alice_client) == []
    added = voice(alice_client, access, "Хлеб", state=ask["session_state"])
    assert added["response"]["end_session"] is True
    assert items(alice_client)[0]["name"] == "Хлеб"
    voice(alice_client, access, "я купил хлеб")
    assert len(items(alice_client)) == 1
    voice(alice_client, access, "добавь в список " + "а" * 201)
    assert len(items(alice_client)) == 1
    cancelled = voice(alice_client, access, "я купил сыр", state=ask["session_state"])
    assert "только в приложении" in cancelled["response"]["text"]
    assert len(items(alice_client)) == 1
    with alice_client.application.app_context():
        assert get_db().execute("SELECT COUNT(*) FROM shopping_purchases").fetchone()[0] == 0


def test_family_is_fixed_to_grant_and_audit_uses_linked_parent(alice_client):
    access = token(alice_client)["access_token"]
    first_family = alice_client.get("/api/me").get_json()["family_id"]
    alice_client.post("/api/families", json={"name": "Another family"})
    voice(alice_client, access, "добавь в список яблоки")
    assert items(alice_client) == []
    with alice_client.application.app_context():
        row = get_db().execute("SELECT * FROM shopping_items").fetchone()
        assert row["family_id"] == first_family
        member = get_db().execute("SELECT * FROM members WHERE id = ?", (row["created_by_member_id"],)).fetchone()
        assert member["family_id"] == first_family


def test_scope_migration_preserves_old_read_only_grants(alice_client):
    original = token(alice_client, "restrictions:read")
    with alice_client.application.app_context():
        db = get_db()
        db.execute("ALTER TABLE alice_grants DROP COLUMN scope")
        db.commit()
        from familyapp.alice_oauth import init_alice
        init_alice()
        assert db.execute("SELECT scope FROM alice_grants").fetchone()[0] == "restrictions:read"
    assert "переподключите" in voice(alice_client, original["access_token"], "что купить")["response"]["text"]


def test_long_list_is_bounded_and_does_not_read_purchase_history(alice_client):
    access = token(alice_client)["access_token"]
    for n in range(24):
        alice_client.post("/api/shopping", json={"name": str(n) + " товар" * 30})
    reply = voice(alice_client, access, "что в списке покупок")
    assert len(reply["response"]["text"]) < 1800
    assert "Остальные товары" in reply["response"]["text"]
