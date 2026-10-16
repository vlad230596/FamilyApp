from datetime import datetime, timedelta, timezone


def test_personal_task_reminds_once_and_can_complete_before_reminder(client, monkeypatch):
    now = datetime(2026, 10, 16, 20, 45, tzinfo=timezone.utc)
    monkeypatch.setattr("familyapp.chores.utc_now", lambda: now)
    member = client.get("/api/me").get_json()["member"]["id"]
    # 30 minutes crosses midnight in Moscow.
    payload = dict(title="Помыть пылесос", responsible_member_id=member, schedule="once",
                   start_date="2026-10-17", reminder_time="00:15", timezone="Europe/Moscow")
    created = client.post("/api/chores", json=payload)
    assert created.status_code == 201
    chore = created.get_json()["chore"]
    reminders = client.get("/api/chores/reminders").get_json()["reminders"]
    assert len(reminders) == 1
    assert datetime.fromisoformat(reminders[0]["scheduled_at"]) == now + timedelta(minutes=30)
    now += timedelta(minutes=16)
    result = client.post(f"/api/chores/{chore['id']}/answers", json=dict(answer=True, occurrence_date="2026-10-17", revision=chore["revision"]))
    assert result.status_code == 200, result.get_json()
    assert client.get("/api/chores/reminders").get_json()["reminders"] == []
    now += timedelta(days=400)
    listed = client.get("/api/chores").get_json()["chores"][0]
    assert listed["due_date"] == "2026-10-17" and listed["due_answer"] is True
    assert listed["next_at"] is None
