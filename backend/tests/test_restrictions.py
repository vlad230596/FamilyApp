from __future__ import annotations

from datetime import date, timedelta

from conftest import PARENT_LOGIN, PARENT_PASSWORD, login_as, make_app


def create_child(client, name="Misha"):
    response = client.post("/api/children", json={"name": name, "icon": "dragon"})
    assert response.status_code == 201
    return response.get_json()["child"]


def create_type(client, name="Cartoons", color="#E53935"):
    response = client.post("/api/restriction-types", json={"name": name, "color": color})
    assert response.status_code == 201
    return response.get_json()["restriction_type"]


def test_create_restriction(client):
    child = create_child(client)
    restriction_type = create_type(client)
    today = date.today()

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=2)).isoformat(),
            "restriction_type_id": restriction_type["id"],
            "reason": "After homework",
        },
    )

    assert response.status_code == 201
    restriction = response.get_json()["restriction"]
    assert restriction["child_id"] == child["id"]
    assert restriction["status"] == "active"
    assert restriction["reason"] == "After homework"
    assert restriction["type_name"] == "Cartoons"
    assert restriction["color"] == "#E53935"


def test_create_and_update_child_icon(client):
    child = create_child(client, name="Anya")

    response = client.post(
        f"/api/children/{child['id']}",
        data={"name": "Anya", "icon": "pet"},
    )

    assert response.status_code == 200
    assert response.get_json()["child"]["icon"] == "pet"
    children = client.get("/api/children").get_json()["children"]
    assert children[0]["icon"] == "pet"


def test_child_icon_persists_in_database(client, database_path):
    child = create_child(client, name="Vera")
    response = client.put(
        f"/api/children/{child['id']}",
        json={"name": "Vera", "icon": "puzzle"},
    )
    assert response.status_code == 200

    restarted_client = login_as(
        make_app(database_path).test_client(), PARENT_LOGIN, PARENT_PASSWORD
    )
    children = restarted_client.get("/api/children").get_json()["children"]

    assert children[0]["icon"] == "puzzle"


def test_create_restriction_type(client):
    restriction_type = create_type(client, name="Tablet", color="#43A047")

    response = client.get("/api/restriction-types")

    assert response.status_code == 200
    assert restriction_type in response.get_json()["restriction_types"]


def test_archive_restriction_type_hides_it_from_default_list(client):
    restriction_type = create_type(client)

    response = client.post(f"/api/restriction-types/{restriction_type['id']}/archive")

    assert response.status_code == 200
    assert response.get_json()["restriction_type"]["archived"] is True
    assert client.get("/api/restriction-types").get_json()["restriction_types"] == []


def test_create_custom_one_off_restriction(client):
    child = create_child(client)
    today = date.today()

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "duration_count": 2,
            "duration_unit": "days",
            "custom_type_name": "No phone",
            "color": "#1E88E5",
            "reason": "",
        },
    )

    assert response.status_code == 201
    restriction = response.get_json()["restriction"]
    assert restriction["type_name"] == "No phone"
    assert restriction["restriction_type_id"] is None
    assert restriction["end_date"] == (today + timedelta(days=1)).isoformat()


def test_restriction_requires_reusable_or_custom_type(client):
    child = create_child(client)
    today = date.today()

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": today.isoformat(),
            "reason": "Missing type",
        },
    )

    assert response.status_code == 400
    assert "restriction_type_id or custom_type_name" in response.get_json()["error"]


def test_invalid_duration_is_rejected(client):
    child = create_child(client)

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": date.today().isoformat(),
            "duration_count": 0,
            "duration_unit": "weeks",
            "custom_type_name": "Games",
            "color": "#8E24AA",
        },
    )

    assert response.status_code == 400


def test_extend_active_restriction(client):
    child = create_child(client)
    restriction_type = create_type(client)
    today = date.today()
    created = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "restriction_type_id": restriction_type["id"],
            "reason": "Tablet",
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
    restriction_type = create_type(client)
    today = date.today()
    created = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "restriction_type_id": restriction_type["id"],
            "reason": "TV",
        },
    ).get_json()["restriction"]

    response = client.post(
        f"/api/restrictions/{created['id']}/cancel",
        json={"note": "Made peace"},
    )

    assert response.status_code == 200
    restriction = response.get_json()["restriction"]
    assert restriction["status"] == "cancelled"
    assert restriction["cancelled_at"] is not None


def test_expired_status_is_computed(client):
    child = create_child(client)
    restriction_type = create_type(client)
    yesterday = date.today() - timedelta(days=1)

    response = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": (yesterday - timedelta(days=2)).isoformat(),
            "end_date": yesterday.isoformat(),
            "restriction_type_id": restriction_type["id"],
            "reason": "Old record",
        },
    )

    assert response.status_code == 201
    assert response.get_json()["restriction"]["status"] == "expired"


def test_cannot_extend_cancelled_restriction(client):
    child = create_child(client)
    restriction_type = create_type(client)
    today = date.today()
    created = client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=1)).isoformat(),
            "restriction_type_id": restriction_type["id"],
            "reason": "Games",
        },
    ).get_json()["restriction"]
    client.post(f"/api/restrictions/{created['id']}/cancel", json={})

    response = client.post(
        f"/api/restrictions/{created['id']}/extend",
        json={"new_end_date": (today + timedelta(days=3)).isoformat()},
    )

    assert response.status_code == 400


def test_today_active_restrictions(client):
    child = create_child(client)
    restriction_type = create_type(client)
    today = date.today()
    client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": today.isoformat(),
            "end_date": (today + timedelta(days=2)).isoformat(),
            "restriction_type_id": restriction_type["id"],
            "reason": "Active today",
        },
    )
    client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": (today + timedelta(days=3)).isoformat(),
            "end_date": (today + timedelta(days=5)).isoformat(),
            "custom_type_name": "Future",
            "color": "#3949AB",
            "reason": "Not today",
        },
    )

    response = client.get(f"/api/restrictions/today?date={today.isoformat()}")

    assert response.status_code == 200
    restrictions = response.get_json()["restrictions"]
    assert len(restrictions) == 1
    assert restrictions[0]["reason"] == "Active today"


def test_date_range_calendar_query(client):
    child = create_child(client)
    restriction_type = create_type(client, color="#FDD835")
    today = date.today()
    client.post(
        "/api/restrictions",
        json={
            "child_id": child["id"],
            "start_date": (today + timedelta(days=4)).isoformat(),
            "duration_count": 2,
            "duration_unit": "weeks",
            "restriction_type_id": restriction_type["id"],
            "reason": "Calendar",
        },
    )

    response = client.get(
        "/api/restrictions/range"
        f"?start_date={today.isoformat()}"
        f"&end_date={(today + timedelta(days=7)).isoformat()}"
    )

    assert response.status_code == 200
    restrictions = response.get_json()["restrictions"]
    assert len(restrictions) == 1
    assert restrictions[0]["color"] == "#FDD835"
