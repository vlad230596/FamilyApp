"""Regression scenarios for the one-shot Alice wave."""
import json
from pathlib import Path
from datetime import datetime, timezone

import pytest

from test_alice import alice_client, exchange, get_code, voice
from test_duties import create, state
from familyapp.persistence import get_db

SCOPES = "restrictions:read&shopping:read&shopping:write&duties:read&duties:write"


def token(client, scope=SCOPES):
    return exchange(client, code=get_code(client, scope=scope)).get_json()["access_token"]


def test_living_scenario_corpus(alice_client):
    corpus = json.loads((Path(__file__).parents[2] / "docs" / "alice-scenarios.json").read_text(encoding="utf-8"))
    access = token(alice_client)
    for scenario in corpus:
        result = voice(alice_client, access, scenario["command"])
        assert result["response"]["end_session"] is True, scenario["id"]
        assert len(result["response"]["text"]) <= 1024, scenario["id"]
        for fragment in scenario["contains"]:
            assert fragment in result["response"]["text"], scenario["id"]
        with alice_client.application.app_context():
            assert get_db().execute("SELECT outcome FROM alice_journal ORDER BY id DESC LIMIT 1").fetchone()[0] == scenario["outcome"], scenario["id"]


@pytest.mark.parametrize("command", ["", "помощь", "справка", "что ты умеешь", "что ты можешь", "команды", "какие команды ты поддерживаешь", "абракадабра", "купить", "можно мультики", "выход"])
def test_every_spoken_response_exits(alice_client, command):
    result = voice(alice_client, token(alice_client), command)
    assert result["response"]["end_session"] is True
    assert len(result["response"]["text"]) <= 1024
    if command in ("помощь", "справка", "что ты умеешь"):
        assert all(word in result["response"]["text"] for word in ("ограничения", "купить", "дежур", "подтвердить"))


def test_voice_draft_never_auto_confirms_linked_parent(alice_client, monkeypatch):
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 7, 9, tzinfo=timezone.utc))
    monkeypatch.setattr("familyapp.alice_voice.local_today", lambda meta: datetime(2026, 10, 7).date())
    create(alice_client, title="помыть посуду")
    name = alice_client.get("/api/me").get_json()["member"]["name"]
    access = token(alice_client)
    assert "помыть посуду" in voice(alice_client, access, "кто сегодня дежурит")["response"]["text"]
    result = voice(alice_client, access, f"{name} выполнил дежурство помыть посуду")
    assert "на подтверждение" in result["response"]["text"]
    row = state(alice_client)["occurrences"][0]
    assert row["status"] == "pending"
    assert row["rating"] is None and row["confirmed_by_member_id"] is None
    path = f"/api/duties/occurrences/{row['id']}"
    assert alice_client.get(path + "/history").get_json()["events"][0]["snapshot"]["source"] == "alice"
    voice(alice_client, access, f"{name} выполнил дежурство помыть посуду")
    assert len(alice_client.get(path + "/history").get_json()["events"]) == 1
    assert alice_client.post(path + "/review", json={"approved": True}).status_code == 200


def test_old_grant_cannot_access_duties(alice_client):
    access = token(alice_client, "restrictions:read")
    assert "переподключите" in voice(alice_client, access, "кто сегодня дежурит")["response"]["text"]


def test_journal_allowlist_review_and_export(alice_client, tmp_path):
    access = token(alice_client)
    voice(alice_client, access, "непонятная команда")
    with alice_client.application.app_context():
        row = dict(get_db().execute("SELECT * FROM alice_journal ORDER BY id DESC LIMIT 1").fetchone())
        assert row["command"] == "непонятная команда"
        assert row["outcome"] == "unrecognized" and row["review"] == "unreviewed"
        assert access not in json.dumps(row)
        family = row["family_id"]
    runner = alice_client.application.test_cli_runner()
    assert runner.invoke(args=["alice-journal-review", str(row["id"]), "--result", "incorrect", "--expected", "New scenario"]).exit_code == 0
    output = tmp_path / "journal.jsonl"
    result = runner.invoke(args=["alice-journal-export", "--family-id", str(family), "--review", "incorrect", "--output", str(output)])
    assert result.exit_code == 0, result.output
    exported = json.loads(output.read_text(encoding="utf-8"))
    assert exported["expected_response"] == "New scenario"
    assert access not in output.read_text(encoding="utf-8")


def test_journal_logs_invalid_request_and_linking(alice_client):
    raw = alice_client.application.test_client()
    assert raw.post("/integrations/alice/webhook", json=[]).status_code == 400
    voice(alice_client, "")
    with alice_client.application.app_context():
        assert [r[0] for r in get_db().execute("SELECT outcome FROM alice_journal ORDER BY id")] == ["invalid_request", "account_linking"]


def test_penalty_is_once_and_excluded_from_statistics(client, monkeypatch):
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 7, 9, tzinfo=timezone.utc))
    member = client.get("/api/me").get_json()["member"]["id"]
    create(client, schedule="once", kind="penalty", assigned_member_id=member)
    reminders = client.get("/api/chores/reminders").get_json()["reminders"]
    assert len([r for r in reminders if r.get("kind") == "duty"]) == 1
    row = state(client)["occurrences"][0]
    assert row["kind"] == "penalty"
    path = f"/api/duties/occurrences/{row['id']}/complete"
    assert client.post(path, json={"rating": "great"}).get_json()["occurrence"]["rating"] is None
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 20, 9, tzinfo=timezone.utc))
    data = state(client)
    assert len(data["occurrences"]) == 1
    stat = data["statistics"][0]
    assert stat["debt"] == stat["completed"] == stat["great"] == 0


def test_duty_ambiguity_away_and_missing_performer_do_not_mutate(alice_client, monkeypatch):
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 7, 9, tzinfo=timezone.utc))
    monkeypatch.setattr("familyapp.alice_voice.local_today", lambda meta: datetime(2026, 10, 7).date())
    create(alice_client, title="помыть посуду")
    create(alice_client, title="помыть посуду")
    name = alice_client.get("/api/me").get_json()["member"]["name"]
    access = token(alice_client)
    for command in (f"{name} выполнил дежурство помыть посуду", "я выполнил дежурство помыть посуду", "отмени дежурство помыть посуду", f"{name} выполнил дежурство помыть посуду завтра"):
        assert voice(alice_client, access, command)["response"]["end_session"] is True
        assert all(row["status"] == "open" for row in state(alice_client)["occurrences"])
    alice_client.post("/api/away-periods", json={"start_date": "2026-10-07", "end_date": "2026-10-07"})
    assert "дежурств нет" in voice(alice_client, access, "кто сегодня дежурит")["response"]["text"]


def test_journal_retention_and_oversize_request(alice_client):
    voice(alice_client, token(alice_client), "помощь")
    with alice_client.application.app_context():
        get_db().execute("UPDATE alice_journal SET created_at = '2000-01-01'")
        get_db().commit()
    response = alice_client.application.test_client().post("/integrations/alice/webhook", json={"padding": "x" * 33000})
    assert response.status_code == 413
    with alice_client.application.app_context():
        rows = get_db().execute("SELECT * FROM alice_journal").fetchall()
        assert len(rows) == 1 and rows[0]["http_status"] == 413


def test_penalty_child_submission_and_review_never_add_rating(client, monkeypatch):
    from test_chores import join
    monkeypatch.setattr("familyapp.duties.utc_now", lambda: datetime(2026, 10, 7, 9, tzinfo=timezone.utc))
    child = join(client, "child")
    member = child.get("/api/me").get_json()["member"]["id"]
    create(client, schedule="once", kind="penalty", assigned_member_id=member)
    row = state(child)["occurrences"][0]
    path = f"/api/duties/occurrences/{row['id']}"
    assert child.post(path + "/complete", json={}).get_json()["occurrence"]["status"] == "pending"
    reviewed = client.post(path + "/review", json={"approved": True, "rating": "great"})
    assert reviewed.get_json()["occurrence"]["rating"] is None
    assert all(s["debt"] == s["completed"] == s["pending"] == s["great"] == 0 for s in state(client)["statistics"])
