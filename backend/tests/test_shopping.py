from datetime import datetime, timedelta, timezone

import pytest

from test_chores import join
from test_families import register_user


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    monkeypatch.setattr("familyapp.shopping.utc_now", lambda: datetime(2026, 10, 7, 9, tzinfo=timezone.utc))


def add(client, name="Milk", urgency="background", **extra):
    response = client.post("/api/shopping", json=dict(name=name, urgency=urgency, **extra))
    assert response.status_code == 201, response.get_json()
    return response.get_json()["item"]


def state(client):
    return client.get("/api/shopping").get_json()


def test_shared_list_child_adds_duplicate_escalates(client):
    child = join(client, "child")
    original = add(child, "  Молоко  ", category="Food")
    assert add(client, "молоко")["id"] == original["id"]
    assert state(child)["items"][0]["urgency"] == "week"
    add(child, "МОЛОКО")
    assert state(client)["items"][0]["urgency"] == "urgent"
    assert state(client)["items"][0]["category"] == "Food"
    assert len(state(client)["items"]) == 1


def test_background_escalation_never_makes_urgent(client, monkeypatch):
    add(client)
    start = datetime(2026, 10, 7, 9, tzinfo=timezone.utc)
    monkeypatch.setattr("familyapp.shopping.utc_now", lambda: start + timedelta(days=29))
    assert state(client)["items"][0]["urgency"] == "background"
    monkeypatch.setattr("familyapp.shopping.utc_now", lambda: start + timedelta(days=30))
    assert state(client)["items"][0]["urgency"] == "week"
    monkeypatch.setattr("familyapp.shopping.utc_now", lambda: start + timedelta(days=100))
    assert state(client)["items"][0]["urgency"] == "week"


def test_purchase_history_return_and_duplicate_merge(client, monkeypatch):
    item = add(client, category="Food")
    path = f"/api/shopping/{item['id']}/buy"
    assert client.post(path, json={"return_in_days": 7}).status_code == 200
    assert client.post(path, json={}).status_code == 400
    assert state(client)["items"] == []
    purchase = state(client)["purchases"][0]
    assert purchase["name"] == "Milk"
    assert purchase["bought_by_name"] == "Mama"
    newer = add(client, urgency="urgent")
    monkeypatch.setattr("familyapp.shopping.utc_now", lambda: datetime(2026, 10, 14, 9, tzinfo=timezone.utc))
    assert state(client)["items"][0]["id"] == newer["id"]
    assert state(client)["items"][0]["urgency"] == "urgent"
    assert state(client)["purchases"][0]["returned_at"] is not None
    assert len(state(client)["items"]) == 1


def test_cancel_return_and_manual_return(client, monkeypatch):
    item = add(client)
    client.post(f"/api/shopping/{item['id']}/buy", json={"return_in_days": 1})
    purchase_id = state(client)["purchases"][0]["id"]
    assert client.post(f"/api/shopping/purchases/{purchase_id}/cancel-return", json={}).status_code == 200
    monkeypatch.setattr("familyapp.shopping.utc_now", lambda: datetime(2026, 10, 9, 9, tzinfo=timezone.utc))
    assert state(client)["items"] == []
    assert client.post(f"/api/shopping/purchases/{purchase_id}/return", json={}).status_code == 200
    assert client.post(f"/api/shopping/purchases/{purchase_id}/return", json={}).status_code == 200
    assert len(state(client)["items"]) == 1


def test_shopping_family_isolation(client):
    item = add(client)
    other = register_user(client.application.test_client())
    other.post("/api/families", json={"name": "Other"})
    assert state(other)["items"] == []
    assert other.post(f"/api/shopping/{item['id']}/buy", json={}).status_code == 400
    client.post(f"/api/shopping/{item['id']}/buy", json={})
    purchase_id = state(client)["purchases"][0]["id"]
    assert other.post(f"/api/shopping/purchases/{purchase_id}/return", json={}).status_code == 400


@pytest.mark.parametrize("payload", [{"name": ""}, {"name": "Milk", "urgency": "wrong"}, {"name": "Milk", "category": "x" * 81}])
def test_validation(client, payload):
    assert client.post("/api/shopping", json=payload).status_code == 400


@pytest.mark.parametrize("days", [0, -1, True, "7", 3651])
def test_invalid_return_period_keeps_item(client, days):
    item = add(client)
    assert client.post(f"/api/shopping/{item['id']}/buy", json={"return_in_days": days}).status_code == 400
    assert len(state(client)["items"]) == 1


def test_multiple_lists_main_and_returns(client, monkeypatch):
    original = add(client)
    main = state(client)['list_id']
    response = client.post('/api/shopping/lists', json={'name': 'Trip'})
    assert response.status_code == 201
    second = response.get_json()['shopping_list']['id']
    item = add(client, list_id=second)
    assert item['id'] != original['id']
    assert len(state(client)['items']) == 1
    assert client.get(f'/api/shopping?list_id={second}').get_json()['items'][0]['id'] == item['id']
    client.post(f"/api/shopping/{item['id']}/buy", json={'return_in_days': 1})
    assert state(client)['purchases'] == []
    client.post(f'/api/shopping/lists/{second}', json={'name': 'Trip', 'is_main': True})
    assert state(client)['list_id'] == second
    assert sum(row['is_main'] for row in state(client)['lists']) == 1
    monkeypatch.setattr('familyapp.shopping.utc_now', lambda: datetime(2026, 10, 9, 9, tzinfo=timezone.utc))
    assert state(client)['items'][0]['list_id'] == second
    assert client.get(f'/api/shopping?list_id={main}').get_json()['items'][0]['id'] == original['id']


def test_list_permissions_and_isolation(client):
    main = state(client)['list_id']
    child = join(client, 'child')
    assert child.post('/api/shopping/lists', json={'name': 'Other'}).status_code == 403
    other = register_user(client.application.test_client())
    other.post('/api/families', json={'name': 'Other'})
    assert other.get(f'/api/shopping?list_id={main}').status_code == 400
    assert other.post('/api/shopping', json={'name': 'Milk', 'list_id': main}).status_code == 400
    assert other.post(f'/api/shopping/lists/{main}', json={'name': 'Changed', 'is_main': True}).status_code == 400
    assert client.get('/api/shopping?list_id=wrong').status_code == 400


def test_existing_single_list_migration(client):
    from familyapp.persistence import get_db
    from familyapp.shopping import init_shopping
    item = add(client, name='Bread')
    client.post(f"/api/shopping/{item['id']}/buy", json={'return_in_days': 7})
    add(client, name='Milk')
    with client.application.app_context():
        db = get_db()
        db.execute('ALTER TABLE shopping_items RENAME TO temp_items')
        db.execute("""CREATE TABLE shopping_items (
            id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL, name TEXT NOT NULL,
            normalized_name TEXT NOT NULL, urgency TEXT NOT NULL, category TEXT NOT NULL,
            created_by_member_id INTEGER NOT NULL, updated_by_member_id INTEGER NOT NULL,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL, urgency_since TEXT NOT NULL,
            UNIQUE(family_id, normalized_name))""")
        db.execute("""INSERT INTO shopping_items SELECT id, family_id, name, normalized_name,
            urgency, category, created_by_member_id, updated_by_member_id, created_at, updated_at,
            urgency_since FROM temp_items""")
        db.execute('DROP TABLE temp_items')
        db.execute('ALTER TABLE shopping_purchases DROP COLUMN list_id')
        db.execute('DROP TABLE shopping_lists')
        db.commit()
        init_shopping()
        init_shopping()
    migrated = state(client)
    assert len(migrated['lists']) == 1
    assert migrated['items'][0]['name'] == 'Milk'
    assert migrated['purchases'][0]['name'] == 'Bread'
    assert migrated['purchases'][0]['return_at'] is not None
    assert migrated['purchases'][0]['list_id'] == migrated['list_id']
