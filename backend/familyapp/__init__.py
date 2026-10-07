from __future__ import annotations

import os
from pathlib import Path

from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException
from werkzeug.security import generate_password_hash

from .persistence import close_db, init_db
from .routes import api
from .cli import register_commands


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    default_db = Path(app.instance_path) / "familyapp.sqlite3"
    app.config.from_mapping(
        DATABASE=os.environ.get("FAMILYAPP_DATABASE", str(default_db)),
        ALICE_CLIENT_ID=os.environ.get("FAMILYAPP_ALICE_CLIENT_ID", ""),
        ALICE_CLIENT_SECRET=os.environ.get("FAMILYAPP_ALICE_CLIENT_SECRET", ""),
        ALICE_COOKIE_SECRET=os.environ.get("FAMILYAPP_ALICE_COOKIE_SECRET", ""),
        ALICE_REDIRECT_URI="https://social.yandex.net/broker/redirect",
        ALICE_SKILL_ID=os.environ.get("FAMILYAPP_ALICE_SKILL_ID", ""),
        ALICE_TIMEZONE=os.environ.get("FAMILYAPP_ALICE_TIMEZONE", "Europe/Moscow"),
        ALICE_COOKIE_SECURE=True,
    )

    if test_config:
        app.config.update(test_config)

    Path(app.instance_path).mkdir(parents=True, exist_ok=True)
    app.teardown_appcontext(close_db)
    app.register_blueprint(api)
    from .alice_routes import alice
    app.register_blueprint(alice)
    app.config["ALICE_DUMMY_HASH"] = generate_password_hash("not-a-real-account")
    register_commands(app)

    @app.after_request
    def add_local_dev_cors_headers(response):
        if not request.path.startswith("/integrations/alice/"):
            response.headers["Access-Control-Allow-Origin"] = "*"
            response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, OPTIONS"
        return response

    @app.errorhandler(HTTPException)
    def handle_http_error(error):
        return jsonify({"error": error.description, "status": error.code}), error.code

    @app.errorhandler(Exception)
    def handle_unexpected_error(error):
        if app.config.get("TESTING"):
            raise error
        return jsonify({"error": "internal server error"}), 500

    with app.app_context():
        init_db()
        from .chores import init_chores
        init_chores()
        from .alice_oauth import init_alice
        init_alice()

    return app
