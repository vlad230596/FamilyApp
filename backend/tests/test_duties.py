from datetime import datetime, timezone

import pytest

from test_chores import join
from test_families import register_user


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 7, 9, tzinfo=timezone.utc))


def create(client, assignee=None, **changes):
    member_id = assignee or client.get("/api/me").get_json()["member"]["id"]
    data = dict(title="Wash dishes", start_date="2026-10-07", weekdays=list(range(1, 8)),
                assignments={str(day): member_id for day in range(1, 8)}, reminder_time="18:00", timezone="Europe/Moscow")
    data.update(changes)
    response = client.post("/api/duties", json=data)
    assert response.status_code == 201, response.get_json()
    return response.get_json()["duty"]


def state(client):
    response = client.get("/api/duties")
    assert response.status_code == 200, response.get_json()
    return response.get_json()


def test_child_confirmation_rating_and_audit(client):
    child = join(client, "child")
    member_id = child.get("/api/me").get_json()["member"]["id"]
    create(client, member_id)
    occurrence = state(child)["occurrences"][0]
    path = f"/api/duties/occurrences/{occurrence['id']}"
    assert child.post(path + "/complete", json={"performer_member_id": 999}).status_code == 400
    assert child.post(path + "/complete", json={"rating": "great"}).get_json()["occurrence"]["status"] == "pending"
    assert child.post(path + "/review", json={"approved": True}).status_code == 403
    assert state(client)["statistics"][1]["completed"] == 0
    result = client.post(path + "/review", json={"approved": True, "rating": "great"}).get_json()["occurrence"]
    assert result["performer_member_id"] == member_id
    assert result["marked_by_member_id"] == member_id
    assert result["confirmed_by_member_id"] != member_id
    assert result["rating"] == "great"
    events = client.get(path + "/history").get_json()["events"]
    assert len(events) == 2
    assert events[0]["actor_name"]
    assert events[0]["snapshot"]["performer_name"]
    assert client.post(path + "/review", json={"approved": True}).status_code == 400
    assert client.post(path + "/complete", json={}).status_code == 400


def test_missed_covered_away_and_suggestion(client, monkeypatch):
    other = join(client)
    assigned = other.get("/api/me").get_json()["member"]["id"]
    parent = client.get("/api/me").get_json()["member"]["id"]
    create(client, assigned)
    first = state(client)["occurrences"][0]
    client.post(f"/api/duties/occurrences/{first['id']}/complete", json={"performer_member_id": parent, "rating": "bad"})
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 9, 9, tzinfo=timezone.utc))
    data = state(client)
    stats = {s["member_id"]: s for s in data["statistics"]}
    assert stats[assigned]["debt"] == 2
    assert stats[parent]["debt"] == -1
    assert stats[parent]["bad"] == 1
    assert data["suggestion"]["member_id"] == assigned
    period = client.post("/api/away-periods", json={"start_date": "2026-10-08", "end_date": "2026-10-09"}).get_json()["period"]
    assert state(client)["suggestion"]["debt"] == 1
    away_occurrence = next(o for o in state(client)["occurrences"] if o["occurrence_date"] == "2026-10-09")
    assert client.post(f"/api/duties/occurrences/{away_occurrence['id']}/complete", json={}).status_code == 400
    assert client.post(f"/api/away-periods/{period['id']}/cancel", json={}).status_code == 200
    assert state(client)["suggestion"]["debt"] == 2


def test_revisions_preserve_today_history_pause_and_reminders(client, monkeypatch):
    other = join(client)
    member_id = other.get("/api/me").get_json()["member"]["id"]
    duty = create(client)
    today = state(client)["occurrences"][0]
    update = {key: duty[key] for key in ("title", "start_date", "weekdays", "assignments", "reminder_time", "timezone", "active")}
    update.update(title="New title", assignments={str(d): member_id for d in range(1, 8)})
    assert client.post(f"/api/duties/{duty['id']}", json=update).status_code == 200
    assert state(client)["occurrences"][0] == today
    reminders = other.get("/api/chores/reminders").get_json()["reminders"]
    assert reminders[0]["occurrence_date"] == "2026-10-08"
    assert reminders[0]["title"] == "New title"
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 8, 9, tzinfo=timezone.utc))
    assert state(client)["occurrences"][0]["assigned_member_id"] == member_id
    update["active"] = False
    assert client.post(f"/api/duties/{duty['id']}", json=update).status_code == 200
    reminders = other.get("/api/chores/reminders").get_json()["reminders"]
    assert len([r for r in reminders if r.get("kind") == "duty"]) == 1


def test_family_and_child_isolation_and_members_without_accounts(client):
    child = join(client, "child")
    duty = create(client)
    item = state(client)["occurrences"][0]
    assert state(child)["occurrences"] == []
    assert child.post(f"/api/duties/occurrences/{item['id']}/complete", json={}).status_code == 403
    assert child.get(f"/api/duties/occurrences/{item['id']}/history").status_code == 403
    other = register_user(client.application.test_client(), "isolated")
    other.post("/api/families", json={"name": "Other"})
    assert other.post(f"/api/duties/{duty['id']}", json=duty).status_code == 400
    assert state(other)["duties"] == []
    member = client.post("/api/members", json={"name": "Baby", "role": "child", "icon": "star"}).get_json()["member"]
    create(client, member["id"])
    assert len(state(client)["duties"]) == 2


def test_rejection_resubmission_and_rating_validation(client):
    child = join(client, "child")
    create(client, child.get("/api/me").get_json()["member"]["id"])
    path = f"/api/duties/occurrences/{state(child)['occurrences'][0]['id']}"
    assert child.post(path + "/complete", json={}).status_code == 200
    assert client.post(path + "/review", json={"approved": True, "rating": "invalid"}).status_code == 400
    assert client.post(path + "/review", json={"approved": False}).status_code == 200
    assert child.post(path + "/complete", json={}).status_code == 200
    assert len(client.get(path + "/history").get_json()["events"]) == 3


@pytest.mark.parametrize("changes", [dict(start_date="2026-10-06"), dict(weekdays=[]), dict(weekdays=[8]),
                                     dict(assignments={"3": 999}), dict(reminder_time="25:00"), dict(timezone="bad")])
def test_invalid_duty(client, changes):
    data = dict(title="Duty", start_date="2026-10-07", weekdays=[3], assignments={}, reminder_time="18:00", timezone="Europe/Moscow")
    data.update(changes)
    assert client.post("/api/duties", json=data).status_code == 400


def test_edit_before_future_start_uses_latest_definition(client, monkeypatch):
    duty = create(client, start_date="2026-10-10")
    updated = dict(duty, title="Edited before start")
    response = client.post(f"/api/duties/{duty['id']}", json=updated)
    assert response.get_json()["duty"]["title"] == "Edited before start"
    assert state(client)["occurrences"] == []
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 11, 9, tzinfo=timezone.utc))
    assert all(o["title"] == "Edited before start" for o in state(client)["occurrences"])


def test_weekdays_and_unassigned_duties_do_not_create_debt(client, monkeypatch):
    create(client, weekdays=[3], assignments={})
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 10, 9, tzinfo=timezone.utc))
    data = state(client)
    assert len(data["occurrences"]) == 1
    assert data["statistics"][0]["debt"] == 0
    assert data["suggestion"] is None


@pytest.mark.parametrize("path", ["/api/duties", "/api/away-periods", "/api/shopping"])
def test_invalid_request_body_is_rejected(client, path):
    assert client.post(path, json=["wrong"]).status_code == 400
