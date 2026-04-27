from __future__ import annotations

from datetime import date, timedelta

import pytest

from familyapp import create_app


@pytest.fixture()
def client(tmp_path):
    app = create_app({"TESTING": True, "DATABASE": str(tmp_path / "test.sqlite3")})
    return app.test_client()


def create_child(client, name="Миша"):
    response = client.post("/api/children", json={"name": name})
    assert response.status_code == 201
    return response.get_json()["child"]


def test_create_restriction(client):
    child = create_child(client)
    today = date.today()

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=2)).isoformat(),
            "reason": "Мультики после уроков",
        },
    )

    assert response.status_code == 201
    restriction = response.get_json()["restriction"]
    assert restriction["child_id"] == child["id"]
    assert restriction["status"] == "active"
    assert restriction["reason"] == "Мультики после уроков"


def test_extend_active_restriction(client):
    child = create_child(client)
    today = date.today()
    created = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "reason": "Планшет",
        },
    ).get_json()["restriction"]

    response = client.post(
        f"/api/restrictions/{created['id']}/extend",
        json={"new_end_date": (today + timedelta(days=3)).isoformat()},
    )

    assert response.status_code == 200
    restriction = response.get_json()["restriction"]
    assert restriction["end_date"] == (today + timedelta(days=3)).isoformat()
    assert restriction["status"] == "active"


def test_cancel_active_restriction(client):
    child = create_child(client)
    today = date.today()
    created = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "reason": "Телевизор",
        },
    ).get_json()["restriction"]

    response = client.post(
        f"/api/restrictions/{created['id']}/cancel",
        json={"note": "Помирились"},
    )

    assert response.status_code == 200
    restriction = response.get_json()["restriction"]
    assert restriction["status"] == "cancelled"
    assert restriction["cancelled_at"] is not None


def test_expired_status_is_computed(client):
    child = create_child(client)
    yesterday = date.today() - timedelta(days=1)

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": (yesterday - timedelta(days=2)).isoformat(),
            "end_date": yesterday.isoformat(),
            "reason": "Старая запись",
        },
    )

    assert response.status_code == 201
    assert response.get_json()["restriction"]["status"] == "expired"


def test_cannot_extend_cancelled_restriction(client):
    child = create_child(client)
    today = date.today()
    created = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "reason": "Игры",
        },
    ).get_json()["restriction"]
    client.post(f"/api/restrictions/{created['id']}/cancel", json={})

    response = client.post(
        f"/api/restrictions/{created['id']}/extend",
        json={"new_end_date": (today + timedelta(days=3)).isoformat()},
    )

    assert response.status_code == 400
