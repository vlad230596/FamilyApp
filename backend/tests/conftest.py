from __future__ import annotations

import pytest

from familyapp import create_app

PARENT_LOGIN = "mama"
PARENT_PASSWORD = "secret-123"


def make_app(database_path):
    return create_app({"TESTING": True, "DATABASE": str(database_path)})


def authorize(client, token: str):
    client.environ_base["HTTP_AUTHORIZATION"] = f"Bearer {token}"
    return client


def setup_parent(client, name="Mama", login=PARENT_LOGIN, password=PARENT_PASSWORD):
    response = client.post(
        "/api/auth/register",
        json={"name": name, "login": login, "password": password},
    )
    assert response.status_code == 201, response.get_json()
    token = response.get_json()["token"]
    authorize(client, token)
    created = client.post("/api/families", json={"name": "Family"})
    assert created.status_code == 201, created.get_json()
    return token


def login_as(client, login, password):
    response = client.post("/api/auth/login", json={"login": login, "password": password})
    assert response.status_code == 200, response.get_json()
    return authorize(client, response.get_json()["token"])


@pytest.fixture()
def database_path(tmp_path):
    return tmp_path / "test.sqlite3"


@pytest.fixture()
def anonymous_client(database_path):
    return make_app(database_path).test_client()


@pytest.fixture()
def client(database_path):
    """A client signed in as the first parent."""
    client = make_app(database_path).test_client()
    return authorize(client, setup_parent(client))
