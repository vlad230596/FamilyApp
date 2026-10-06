from datetime import date, datetime, timezone
import sqlite3

import pytest

from familyapp.chores import scheduled_on
from test_families import register_user


@pytest.fixture(autouse=True)
def fixed_clock(monkeypatch):
    monkeypatch.setattr('familyapp.chores.utc_now', lambda: datetime(2026, 10, 7, 20, 30, tzinfo=timezone.utc))


def payload(client, **changes):
    return dict(title='Dishwasher running?',
                responsible_member_id=client.get('/api/me').get_json()['member']['id'],
                start_date='2026-10-07', interval_days=1, weekdays=[],
                reminder_time='23:00', timezone='Europe/Moscow', **changes)


def create(client, **changes):
    data = payload(client)
    data.update(changes)
    response = client.post('/api/chores', json=data)
    assert response.status_code == 201, response.get_json()
    return response.get_json()['chore']


def join(client, role='parent', login='other'):
    code = client.post('/api/invitations', json={'role': role}).get_json()['code']
    other = register_user(client.application.test_client(), login)
    assert other.post('/api/invitations/accept', json={'code': code}).status_code == 200
    return other


def answer(client, chore, value=True, day='2026-10-07', **changes):
    data = dict(answer=value, occurrence_date=day, revision=chore['revision'])
    data.update(changes)
    return client.post(f"/api/chores/{chore['id']}/answers", json=data)


def test_daily_check_answer_history_and_next_reminder(client):
    chore = create(client)
    assert chore['due_date'] == '2026-10-07'
    assert chore['due_answer'] is None
    assert chore['next_at'] == '2026-10-08T23:00:00+03:00'
    assert answer(client, chore, False).get_json()['chore']['due_answer'] is False
    assert answer(client, chore, False).status_code == 200
    assert answer(client, chore, True).status_code == 400
    history = client.get(f"/api/chores/{chore['id']}/answers").get_json()['answers']
    assert len(history) == 1
    assert history[0]['answer'] is False
    assert history[0]['actor_member_id'] == chore['responsible_member_id']
    reminders = client.get('/api/chores/reminders').get_json()['reminders']
    assert len(reminders) == 59
    assert reminders[0]['occurrence_date'] == '2026-10-08'


def test_only_assignee_can_answer_and_receive_reminders(client):
    other = join(client)
    chore = create(client)
    assert len(other.get('/api/chores').get_json()['chores']) == 1
    assert other.get('/api/chores/reminders').get_json()['reminders'] == []
    assert answer(other, chore).status_code == 403
    assert answer(client, chore).status_code == 200


def test_child_can_answer_own_checks_but_cannot_manage_or_see_others(client):
    child = join(client, 'child')
    child_id = child.get('/api/me').get_json()['member']['id']
    own = create(client, responsible_member_id=child_id)
    parents = create(client)
    assert [c['id'] for c in child.get('/api/chores').get_json()['chores']] == [own['id']]
    assert len(child.get('/api/chores/reminders').get_json()['reminders']) == 59
    assert answer(child, own).status_code == 200
    assert answer(client, own).status_code == 403
    assert child.post('/api/chores', json=payload(child)).status_code == 403
    assert child.post(f"/api/chores/{own['id']}", json=payload(child)).status_code == 403
    assert child.get(f"/api/chores/{parents['id']}/answers").status_code == 403


def test_family_isolation_and_assignment(client):
    chore = create(client)
    other = register_user(client.application.test_client())
    other.post('/api/families', json={'name': 'Other'})
    assert other.get('/api/chores').get_json()['chores'] == []
    assert answer(other, chore).status_code == 400
    assert other.get(f"/api/chores/{chore['id']}/answers").status_code == 400
    assert other.post(f"/api/chores/{chore['id']}", json=payload(other)).status_code == 400
    data = payload(other)
    data['responsible_member_id'] = chore['responsible_member_id']
    assert other.post('/api/chores', json=data).status_code == 400


def test_interval_and_weekdays_are_anchored_to_start_date():
    chore = dict(start_date='2026-10-07', interval_days=7, weekdays=[])
    assert scheduled_on(chore, date(2026, 10, 7))
    assert scheduled_on(chore, date(2026, 10, 14))
    assert not scheduled_on(chore, date(2026, 10, 8))
    assert not scheduled_on(chore, date(2026, 9, 30))
    chore.update(interval_days=1, weekdays=[1, 5])
    assert scheduled_on(chore, date(2026, 10, 9))
    assert scheduled_on(chore, date(2026, 10, 12))
    assert not scheduled_on(chore, date(2026, 10, 7))


def test_no_early_answers_and_timezone_date_boundaries(client):
    future = create(client, reminder_time='23:59')
    assert future['due_date'] is None
    assert answer(client, future).status_code == 400
    assert answer(client, future, day='2026-10-08').status_code == 400
    eastern = create(client, timezone='Asia/Vladivostok', reminder_time='06:00')
    assert eastern['due_date'] == '2026-10-08'
    assert answer(client, eastern, day='2026-10-08').status_code == 200
    weekly = create(client, interval_days=7)
    assert answer(client, weekly, day='2026-10-06').status_code == 400


def test_reassignment_stale_actions_pause_and_audit(client, database_path):
    chore = create(client)
    assert answer(client, chore).status_code == 200
    other = join(client)
    data = payload(client)
    data.update(responsible_member_id=other.get('/api/me').get_json()['member']['id'], title='New title')
    updated = client.post(f"/api/chores/{chore['id']}", json=data).get_json()['chore']
    assert updated['revision'] == 2
    assert answer(client, updated).status_code == 403
    assert answer(other, chore).status_code == 400
    assert answer(other, updated).status_code == 400  # Existing answer belongs to its original actor.
    assert client.get('/api/chores/reminders').get_json()['reminders'] == []
    assert len(other.get('/api/chores/reminders').get_json()['reminders']) == 59
    data['active'] = False
    paused = client.post(f"/api/chores/{chore['id']}", json=data).get_json()['chore']
    assert paused['due_date'] is None
    assert answer(other, paused).status_code == 400
    assert other.get('/api/chores/reminders').get_json()['reminders'] == []
    history = client.get(f"/api/chores/{chore['id']}/answers").get_json()['answers']
    assert history[0]['title'] == 'Dishwasher running?'
    with sqlite3.connect(database_path) as db:
        assert db.execute('SELECT COUNT(*) FROM chore_events').fetchone()[0] == 3


@pytest.mark.parametrize('field,value', [
    ('title', ''), ('title', 123), ('interval_days', 0), ('interval_days', 366),
    ('interval_days', True), ('interval_days', 1.5), ('weekdays', [0]), ('weekdays', [True]),
    ('weekdays', 'Monday'), ('reminder_time', '24:00'), ('reminder_time', '9:00'),
    ('timezone', 'unknown'), ('timezone', None), ('start_date', 'invalid'), ('active', 'false'),
    ('responsible_member_id', None),
])
def test_invalid_schedule(client, field, value):
    data = payload(client)
    data[field] = value
    assert client.post('/api/chores', json=data).status_code == 400


def test_member_without_account_cannot_be_assigned(client):
    member = client.post('/api/members', json={'name': 'Small child', 'role': 'child', 'icon': 'star'}).get_json()['member']
    data = payload(client)
    data['responsible_member_id'] = member['id']
    assert client.post('/api/chores', json=data).status_code == 400


def test_invalid_answer_and_reminder_limit(client):
    chore = create(client)
    assert answer(client, chore, value='yes').status_code == 400
    assert answer(client, chore, revision=None).status_code == 400
    for _ in range(4):
        create(client)
    assert len(client.get('/api/chores/reminders').get_json()['reminders']) == 200
