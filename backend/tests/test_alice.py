from __future__ import annotations

import base64
import re
from datetime import date, timedelta
from urllib.parse import parse_qs, urlparse

import pytest

from conftest import PARENT_LOGIN, PARENT_PASSWORD, authorize, setup_parent
from familyapp.persistence import get_db

REDIRECT = "https://social.yandex.net/broker/redirect"


@pytest.fixture()
def alice_client(client):
    client.application.config.update(ALICE_CLIENT_ID="familyapp-alice", ALICE_CLIENT_SECRET="test-client-secret",
                                     ALICE_COOKIE_SECRET="test-cookie-secret", ALICE_COOKIE_SECURE=False,
                                     ALICE_SKILL_ID="test-skill")
    return client


def csrf(response):
    return re.search(r'name="csrf" value="([^"]+)"', response.get_data(as_text=True))[1]


def get_code(client, family_id=None, scope="restrictions:read"):
    browser = client.application.test_client()
    response = browser.get("/integrations/alice/authorize", query_string={
        "client_id": "familyapp-alice", "redirect_uri": REDIRECT, "response_type": "code",
        "scope": scope, "state": "opaque state & русский"})
    assert response.status_code == 200
    response = browser.post("/integrations/alice/authorize", data={
        "csrf": csrf(response), "login": PARENT_LOGIN, "password": PARENT_PASSWORD})
    assert response.status_code == 200
    if family_id is None:
        family_id = client.get("/api/me").get_json()["family_id"]
    response = browser.post("/integrations/alice/authorize", data={
        "csrf": csrf(response), "action": "allow", "family_id": family_id})
    assert response.status_code == 302
    parsed = parse_qs(urlparse(response.location).query)
    assert parsed["state"] == ["opaque state & русский"]
    return parsed["code"][0]


def exchange(client, **kwargs):
    return client.post("/integrations/alice/token", data={
        "client_id": "familyapp-alice", "client_secret": "test-client-secret",
        "grant_type": "authorization_code", "redirect_uri": REDIRECT, **kwargs})


def linked_token(client):
    response = exchange(client, code=get_code(client))
    assert response.status_code == 200
    return response.get_json()


def voice(client, access, command="какие сегодня ограничения у ребят", state=None, **kwargs):
    payload = {"version": "1.0", "meta": {"timezone": "Europe/Moscow", "interfaces": {"account_linking": {}}},
               "session": {"skill_id": "test-skill", "user": {"access_token": access}},
               "request": {"type": "SimpleUtterance", "command": command}, **kwargs}
    if state:
        payload["state"] = {"session": state}
    # Do not reuse the app's Bearer session as webhook authentication.
    response = client.application.test_client().post("/integrations/alice/webhook", json=payload)
    assert response.status_code == 200, response.get_json()
    return response.get_json()


def restriction(client, name="Михаил", start="2026-10-07", end="2026-10-08", label="Мультфильмы"):
    children = client.get("/api/children").get_json()["children"]
    child = next((c for c in children if c["name"] == name), None)
    if child is None:
        child = client.post("/api/children", json={"name": name}).get_json()["child"]
    response = client.post("/api/restrictions", json={"child_id": child["id"], "start_date": start,
        "end_date": end, "custom_type_name": label, "reason": "Sensitive reason"})
    assert response.status_code == 201, response.get_json()
    return response.get_json()["restriction"]


def fixed_day(monkeypatch, day="2026-10-07"):
    class FixedDate(date):
        @classmethod
        def today(cls):
            return cls.fromisoformat(day)

    monkeypatch.setattr("familyapp.domain.date", FixedDate)
    monkeypatch.setattr("familyapp.persistence.date", FixedDate)
    monkeypatch.setattr("familyapp.alice_voice.local_today", lambda meta: date.fromisoformat(day))


def test_disabled_without_configuration(client):
    assert client.get("/integrations/alice/manage").status_code == 503
    assert client.post("/integrations/alice/webhook", json={}).status_code == 503


def test_oauth_consent_refresh_replay_and_scope(alice_client):
    code = get_code(alice_client)
    assert exchange(alice_client, code=code, redirect_uri="https://evil.example").status_code == 400
    assert exchange(alice_client, code=code, client_secret="ошибка").status_code == 401
    tokens = exchange(alice_client, code=code).get_json()
    assert tokens["scope"] == "restrictions:read"
    assert tokens["expires_in"] == 3600
    assert exchange(alice_client, code=code).get_json()["error"] == "invalid_grant"
    refreshed = exchange(alice_client, grant_type="refresh_token", refresh_token=tokens["refresh_token"])
    assert refreshed.status_code == 200
    assert refreshed.get_json()["access_token"] != tokens["access_token"]
    assert exchange(alice_client, grant_type="refresh_token", refresh_token=tokens["refresh_token"]).status_code == 400
    assert exchange(alice_client, grant_type="refresh_token", refresh_token=refreshed.get_json()["refresh_token"], scope="write").status_code == 400
    with alice_client.application.app_context():
        row = get_db().execute("SELECT * FROM alice_tokens LIMIT 1").fetchone()
        assert row["access_hash"] != tokens["access_token"]
        assert row["refresh_hash"] != tokens["refresh_token"]
    assert "start_account_linking" not in voice(alice_client, tokens["access_token"])
    assert alice_client.get("/api/children", headers={"Authorization": "Bearer " + tokens["access_token"]}).status_code == 401


def test_basic_client_authentication(alice_client):
    code = get_code(alice_client)
    basic = base64.b64encode(b"familyapp-alice:test-client-secret").decode()
    response = alice_client.post("/integrations/alice/token", headers={"Authorization": "Basic " + basic},
                                 data={"grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT})
    assert response.status_code == 200


def test_authorization_validation_csrf_and_denial(alice_client):
    browser = alice_client.application.test_client()
    args = {"client_id": "familyapp-alice", "redirect_uri": "https://evil.example", "response_type": "code"}
    assert browser.get("/integrations/alice/authorize", query_string=args).status_code == 400
    args["redirect_uri"] = REDIRECT
    args["scope"] = "write"
    assert browser.get("/integrations/alice/authorize", query_string=args).status_code == 400
    args["scope"] = "restrictions:read"
    response = browser.get("/integrations/alice/authorize", query_string=args)
    assert "HttpOnly" in response.headers["Set-Cookie"]
    assert response.headers["Cache-Control"] == "no-store"
    assert "Access-Control-Allow-Origin" not in response.headers
    assert browser.post("/integrations/alice/authorize", data={"csrf": "чужой"}).status_code == 400
    denied = browser.post("/integrations/alice/authorize", data={"csrf": csrf(response), "action": "deny"})
    assert parse_qs(urlparse(denied.location).query)["error"] == ["access_denied"]


def test_parent_login_throttled(alice_client):
    browser = alice_client.application.test_client()
    response = browser.get("/integrations/alice/manage")
    for _ in range(10):
        response = browser.post("/integrations/alice/manage", data={"csrf": csrf(response), "login": "nobody", "password": "wrong"})
        assert response.status_code == 401
    response = browser.post("/integrations/alice/manage", data={"csrf": csrf(response), "login": "nobody", "password": "wrong"})
    assert response.status_code == 429


def test_child_cannot_link_or_select_another_family(alice_client):
    other = alice_client.application.test_client()
    setup_parent(other, name="Other", login="other", password="secret-456")
    other_family = other.get("/api/me").get_json()["family_id"]
    browser = alice_client.application.test_client()
    response = browser.get("/integrations/alice/authorize", query_string={
        "client_id": "familyapp-alice", "redirect_uri": REDIRECT, "response_type": "code"})
    response = browser.post("/integrations/alice/authorize", data={"csrf": csrf(response), "login": PARENT_LOGIN, "password": PARENT_PASSWORD})
    response = browser.post("/integrations/alice/authorize", data={"csrf": csrf(response), "family_id": other_family})
    assert response.status_code == 403
    invitation = alice_client.post("/api/invitations", json={"role": "child"}).get_json()["code"]
    child = alice_client.application.test_client()
    registered = child.post("/api/auth/register", json={"name": "Child", "login": "child", "password": "secret-789"})
    authorize(child, registered.get_json()["token"])
    child.post("/api/invitations/accept", json={"code": invitation})
    response = child.get("/integrations/alice/manage")
    assert child.post("/integrations/alice/manage", data={"csrf": csrf(response), "login": "child", "password": "secret-789"}).status_code == 401


def test_webhook_linking_shape_skill_and_invalid_body(alice_client):
    result = voice(alice_client, "invalid")
    assert result == {"version": "1.0", "start_account_linking": {}}
    result = voice(alice_client, "invalid", meta={"interfaces": {}})
    assert result["response"]["end_session"]
    browser = alice_client.application.test_client()
    assert browser.post("/integrations/alice/webhook", json=[]).status_code == 400
    assert browser.post("/integrations/alice/webhook", json={"version": "1.0", "session": {"skill_id": "other"}}).status_code == 403
    assert browser.post("/integrations/alice/webhook", data="x" * 33000).status_code == 413


def test_token_expiry_and_password_change(alice_client):
    tokens = linked_token(alice_client)
    with alice_client.application.app_context():
        db = get_db()
        db.execute("UPDATE alice_tokens SET access_expires_at = '2000-01-01'")
        db.commit()
    assert "start_account_linking" in voice(alice_client, tokens["access_token"])
    renewed = exchange(alice_client, grant_type="refresh_token", refresh_token=tokens["refresh_token"]).get_json()
    member_id = alice_client.get("/api/me").get_json()["member"]["id"]
    response = alice_client.post(f"/api/members/{member_id}/credentials", json={"login": PARENT_LOGIN, "password": "changed-123"})
    assert response.status_code == 200
    assert "start_account_linking" in voice(alice_client, renewed["access_token"])
    assert exchange(alice_client, grant_type="refresh_token", refresh_token=renewed["refresh_token"]).status_code == 400


def test_manage_revocation(alice_client):
    tokens = linked_token(alice_client)
    browser = alice_client.application.test_client()
    response = browser.get("/integrations/alice/manage")
    response = browser.post("/integrations/alice/manage", data={"csrf": csrf(response), "login": PARENT_LOGIN, "password": PARENT_PASSWORD})
    grant_id = re.search(r'name="grant_id" value="(\d+)"', response.get_data(as_text=True))[1]
    response = browser.post("/integrations/alice/manage", data={"csrf": csrf(response), "grant_id": grant_id})
    assert response.status_code == 200
    assert "start_account_linking" in voice(alice_client, tokens["access_token"])
    assert exchange(alice_client, grant_type="refresh_token", refresh_token=tokens["refresh_token"]).status_code == 400


def test_summary_filtering_and_read_only(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client)
    canceled = restriction(alice_client, label="Телефон")
    assert alice_client.post(f"/api/restrictions/{canceled['id']}/cancel", json={}).status_code == 200
    restriction(alice_client, name="Мария", start="2026-10-09", end="2026-10-10")
    tokens = linked_token(alice_client)
    result = voice(alice_client, tokens["access_token"])
    text = result["response"]["text"]
    assert "Михаил" in text and "Мультфильмы" in text
    assert "Телефон" not in text and "Мария" not in text and "Sensitive reason" not in text
    assert "08.10.2026" in text
    before = alice_client.get("/api/restrictions").get_json()
    text = voice(alice_client, tokens["access_token"], "отмени Мише ограничение на мультики")["response"]["text"]
    assert "только в приложении" in text
    assert alice_client.get("/api/restrictions").get_json() == before


@pytest.mark.parametrize("phrase", ["можно Мише сегодня мультики", "Миша сегодня может смотреть мультфильмы", "когда Михаилу снова можно мультики"])
def test_permission_and_contiguous_periods(alice_client, monkeypatch, phrase):
    fixed_day(monkeypatch)
    restriction(alice_client)
    restriction(alice_client, start="2026-10-09", end="2026-10-11")
    restriction(alice_client, start="2026-10-13", end="2026-10-14")
    tokens = linked_token(alice_client)
    text = voice(alice_client, tokens["access_token"], phrase)["response"]["text"]
    assert "12.10.2026" in text


def test_followups_unknown_names_context_and_dates(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client, end="2026-10-07")
    tokens = linked_token(alice_client)
    first = voice(alice_client, tokens["access_token"], "можно Мише сегодня мультики")
    tomorrow = voice(alice_client, tokens["access_token"], "а завтра", first["session_state"])
    assert "08.10.2026 нет ограничения" in tomorrow["response"]["text"]
    unknown = voice(alice_client, tokens["access_token"], "а у Пети", first["session_state"])
    assert "Не нашла" in unknown["response"]["text"]
    invalid = voice(alice_client, tokens["access_token"], "какие ограничения завтра и сегодня")
    assert "Уточните один день" in invalid["response"]["text"]
    unsupported = voice(alice_client, tokens["access_token"], "ограничения в пятницу")
    assert "Уточните один день" in unsupported["response"]["text"]
    tampered = voice(alice_client, tokens["access_token"], "а завтра", {"context": "forged"})
    assert "пока отвечаю" in tampered["response"]["text"]
    ask = voice(alice_client, tokens["access_token"], "можно сегодня мультики")
    assert "Про какого" in ask["response"]["text"]
    clarified = voice(alice_client, tokens["access_token"], "Миша", ask["session_state"])
    assert "08.10.2026" in clarified["response"]["text"]


def test_ambiguous_names_and_types(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client, name="Александр")
    restriction(alice_client, name="Александра")
    restriction(alice_client)
    tokens = linked_token(alice_client)
    assert "Уточните одного" in voice(alice_client, tokens["access_token"], "что нельзя Саше")["response"]["text"]
    assert "Уточните одно занятие" in voice(alice_client, tokens["access_token"], "можно Мише мультики и телефон")["response"]["text"]


def test_family_isolation_and_selection_is_fixed(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client)
    tokens = linked_token(alice_client)
    alice_client.post("/api/families", json={"name": "Second family"})
    restriction(alice_client, name="Secret child")
    text = voice(alice_client, tokens["access_token"])["response"]["text"]
    assert "Михаил" in text and "Secret child" not in text
    other_tokens = linked_token(alice_client)
    text = voice(alice_client, other_tokens["access_token"])["response"]["text"]
    assert "Secret child" in text and "Михаил" not in text
    assert voice(alice_client, other_tokens["access_token"], "что нельзя Мише")["response"]["text"].startswith("Не нашла")


def test_timezone_and_bounded_answers(alice_client, monkeypatch):
    from familyapp.alice_voice import local_today
    with alice_client.application.app_context():
        assert isinstance(local_today({"timezone": "Pacific/Kiritimati"}), date)
        assert isinstance(local_today({"timezone": "invalid"}), date)
    fixed_day(monkeypatch)
    for i in range(24):
        restriction(alice_client, label="Длинное ограничение " + str(i) + " x" * 60)
    tokens = linked_token(alice_client)
    result = voice(alice_client, tokens["access_token"])
    assert len(result["response"]["text"]) < 1800
    assert "Остальные ограничения" in result["response"]["text"]


def test_empty_help_and_link_complete(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    tokens = linked_token(alice_client)
    assert "ограничений в FamilyApp нет" in voice(alice_client, tokens["access_token"])["response"]["text"]
    assert "Можно спросить" in voice(alice_client, tokens["access_token"], "")["response"]["text"]
    assert voice(alice_client, tokens["access_token"], "выход")["response"]["end_session"]
    assert "ограничений в FamilyApp нет" in voice(alice_client, tokens["access_token"], "", account_linking_complete_event={})["response"]["text"]


def test_expired_code_refresh_and_removed_parent(alice_client):
    code = get_code(alice_client)
    with alice_client.application.app_context():
        get_db().execute("UPDATE alice_codes SET expires_at = '2000-01-01'")
        get_db().commit()
    assert exchange(alice_client, code=code).status_code == 400
    tokens = linked_token(alice_client)
    with alice_client.application.app_context():
        get_db().execute("UPDATE alice_tokens SET refresh_expires_at = '2000-01-01'")
        get_db().commit()
    assert exchange(alice_client, grant_type="refresh_token", refresh_token=tokens["refresh_token"]).status_code == 400
    with alice_client.application.app_context():
        get_db().execute("UPDATE members SET role = 'child' WHERE user_id IS NOT NULL")
        get_db().commit()
    assert "start_account_linking" in voice(alice_client, tokens["access_token"])


def test_unknown_names_and_unsupported_dates_never_read_summary(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client)
    tokens = linked_token(alice_client)
    for phrase in ("что нельзя Петру", "ограничения у Кузьмы", "ограничения Кузьмы", "Петя сегодня может смотреть мультфильмы"):
        assert "Не нашла" in voice(alice_client, tokens["access_token"], phrase)["response"]["text"]
    for phrase in ("ограничения на 10 октября", "ограничения через неделю", "ограничения на 31 декабря"):
        assert "Уточните один день" in voice(alice_client, tokens["access_token"], phrase)["response"]["text"]
    assert "Уточните один день" in voice(alice_client, tokens["access_token"], "ограничения 2026-10-07 и 2026-10-08")["response"]["text"]


def test_clarification_custom_topic_and_signed_context_bound_to_grant(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client, label="Сладкое")
    tokens = linked_token(alice_client)
    initial = voice(alice_client, tokens["access_token"], "можно Мише")
    assert "Какое занятие" in initial["response"]["text"]
    clarified = voice(alice_client, tokens["access_token"], "сладкое", initial["session_state"])
    assert "Сладкое" in clarified["response"]["text"]
    other = linked_token(alice_client)
    denied_context = voice(alice_client, other["access_token"], "а завтра", clarified["session_state"])
    assert "пока отвечаю" in denied_context["response"]["text"]
    all_children = voice(alice_client, tokens["access_token"], "а у всех", clarified["session_state"])
    assert "Ограничения на" in all_children["response"]["text"]


def test_exact_date_queries_and_overlapping_last_day(alice_client, monkeypatch):
    fixed_day(monkeypatch)
    restriction(alice_client, end="2026-10-08")
    restriction(alice_client, start="2026-10-08", end="2026-10-10")
    tokens = linked_token(alice_client)
    last_day = voice(alice_client, tokens["access_token"], "можно Мише мультики 2026-10-10")
    assert "действует ограничение" in last_day["response"]["text"]
    assert "11.10.2026" in last_day["response"]["text"]
    free = voice(alice_client, tokens["access_token"], "можно Мише мультики 2026-10-11")
    assert "нет ограничения" in free["response"]["text"]


def test_conflicting_header_and_app_session_rejected(alice_client):
    tokens = linked_token(alice_client)
    body = {"version": "1.0", "meta": {"interfaces": {"account_linking": {}}},
            "session": {"skill_id": "test-skill", "user": {"access_token": tokens["access_token"]}}}
    # The fixture's Authorization header is a normal app session, not an Alice token.
    response = alice_client.post("/integrations/alice/webhook", json=body)
    assert response.get_json() == {"version": "1.0", "start_account_linking": {}}
    body["session"]["user"].pop("access_token")
    assert alice_client.post("/integrations/alice/webhook", json=body).get_json() == {"version": "1.0", "start_account_linking": {}}
