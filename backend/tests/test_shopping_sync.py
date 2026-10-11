from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from test_chores import join
from test_families import register_user

NOW = datetime(2026, 10, 12, 12, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    monkeypatch.setattr('familyapp.shopping.utc_now', lambda: NOW)


def operation(client, kind, **values):
    family_id = client.get('/api/me').get_json()['family_id']
    return dict(operation_id=uuid4().hex, family_id=family_id, kind=kind,
                occurred_at=(NOW - timedelta(hours=2)).isoformat(), **values)


def sync(client, command):
    response = client.post('/api/shopping/sync', json=command)
    assert response.status_code == 200, response.get_json()
    return response.get_json()


def snapshot(client):
    response = client.get('/api/shopping/snapshot')
    assert response.status_code == 200
    return response.get_json()


def main_list(client):
    return snapshot(client)['lists'][0]['id']


def addition(client, name='Milk', **values):
    return operation(client, 'add', name=name, category='', urgency='week',
                     list_id=main_list(client), **values)


def test_offline_add_then_buy_retries_are_exactly_once(client):
    add = addition(client)
    first = sync(client, add)
    assert sync(client, add) == first
    buy = operation(client, 'buy', add_operation_id=add['operation_id'], return_in_days=7)
    purchased = sync(client, buy)
    assert sync(client, buy) == purchased
    data = snapshot(client)['snapshots'][0]
    assert data['items'] == []
    assert len(data['purchases']) == 1
    assert datetime.fromisoformat(data['purchases'][0]['bought_at']) == NOW - timedelta(hours=2)
    assert datetime.fromisoformat(data['purchases'][0]['return_at']) == NOW - timedelta(hours=2) + timedelta(days=7)


def test_duplicate_additions_merge_urgency_preserve_existing_category(client):
    first = addition(client, name='Молоко')
    first.update(category='Еда', urgency='urgent')
    result = sync(client, first)
    second = addition(client, name='  МОЛОКО  ')
    second['category'] = 'Напитки'
    assert sync(client, second)['item_key'] == result['item_key']
    item = snapshot(client)['snapshots'][0]['items'][0]
    assert item['urgency'] == 'urgent'
    assert item['category'] == 'Еда'


def test_concurrent_buy_one_history_entry_and_new_occurrence_survives(client):
    child = join(client, 'child')
    original = sync(client, addition(client))
    # The existing online API also records the immutable source identity.
    assert client.post(f"/api/shopping/{original['item_id']}/buy", json={}).status_code == 200
    newer = sync(client, addition(client))
    assert newer['item_key'] != original['item_key']
    stale = operation(child, 'buy', item_key=original['item_key'], return_in_days=None)
    result = sync(child, stale)
    assert result['status'] == 'already_bought'
    data = snapshot(client)['snapshots'][0]
    assert len(data['purchases']) == 1
    assert [item['item_key'] for item in data['items']] == [newer['item_key']]


@pytest.mark.parametrize('choice,days', [('server', 7), ('local', 3)])
def test_return_period_conflict_is_resolved_explicitly(client, choice, days):
    child = join(client, 'child')
    item = sync(client, addition(client))
    sync(client, operation(client, 'buy', item_key=item['item_key'], return_in_days=7))
    buy = operation(child, 'buy', item_key=item['item_key'], return_in_days=3)
    conflict = sync(child, buy)
    assert conflict['status'] == 'conflict'
    assert conflict['return_in_days'] == 7
    resolve = operation(child, 'resolve', conflict_operation_id=buy['operation_id'], choice=choice)
    result = sync(child, resolve)
    assert result['status'] == 'applied'
    assert result['return_in_days'] == days
    assert sync(child, resolve) == result
    assert len(snapshot(client)['snapshots'][0]['purchases']) == 1


def test_returned_purchase_cannot_be_changed_by_late_conflict(client):
    item = sync(client, addition(client))
    purchase = sync(client, operation(client, 'buy', item_key=item['item_key'], return_in_days=7))
    buy = operation(client, 'buy', item_key=item['item_key'], return_in_days=3)
    sync(client, buy)
    client.post(f"/api/shopping/purchases/{purchase['purchase_id']}/return", json={})
    result = sync(client, operation(client, 'resolve', conflict_operation_id=buy['operation_id'], choice='local'))
    assert result['status'] == 'conflict'
    assert result['can_change'] is False
    assert len(snapshot(client)['snapshots'][0]['items']) == 1


def test_sync_scope_and_receipts_do_not_cross_families_or_members(client):
    add = addition(client)
    original = sync(client, add)
    other = register_user(client.application.test_client())
    other.post('/api/families', json={'name': 'Other'})
    assert other.post('/api/shopping/sync', json=add).status_code == 400
    stolen_buy = operation(other, 'buy', item_key=original['item_key'], return_in_days=None)
    assert other.post('/api/shopping/sync', json=stolen_buy).status_code == 400
    child = join(client, 'child')
    dependent = operation(child, 'buy', add_operation_id=add['operation_id'], return_in_days=None)
    assert child.post('/api/shopping/sync', json=dependent).status_code == 400


def test_operation_id_cannot_be_reused_for_different_payload(client):
    add = addition(client)
    sync(client, add)
    add['name'] = 'Bread'
    assert client.post('/api/shopping/sync', json=add).status_code == 400
    assert len(snapshot(client)['snapshots'][0]['items']) == 1


def test_snapshot_contains_all_lists_for_offline_use(client):
    first = main_list(client)
    second = client.post('/api/shopping/lists', json={'name': 'Дача'}).get_json()['shopping_list']['id']
    for list_id, name in [(first, 'Хлеб'), (second, 'Вода')]:
        command = addition(client, name=name)
        command['list_id'] = list_id
        sync(client, command)
    data = snapshot(client)
    assert len(data['lists']) == len(data['snapshots']) == 2
    assert {row['items'][0]['name'] for row in data['snapshots']} == {'Хлеб', 'Вода'}


@pytest.mark.parametrize('values', [
    {'return_in_days': True}, {'return_in_days': 0},
    {'occurred_at': 'broken'}, {'occurred_at': '2026-10-12T12:00:00'},
    {'occurred_at': '2030-01-01T00:00:00+00:00'},
])
def test_invalid_purchase_does_not_remove_item(client, values):
    item = sync(client, addition(client))
    command = operation(client, 'buy', item_key=item['item_key'], return_in_days=None)
    command.update(values)
    assert client.post('/api/shopping/sync', json=command).status_code == 400
    assert len(snapshot(client)['snapshots'][0]['items']) == 1
