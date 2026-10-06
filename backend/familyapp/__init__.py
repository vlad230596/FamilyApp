from __future__ import annotations

import os
from pathlib import Path

from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException

from .persistence import close_db, init_db
from .routes import api
from .cli import register_commands


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    default_db = Path(app.instance_path) / "familyapp.sqlite3"
    app.config.from_mapping(
        DATABASE=os.environ.get("FAMILYAPP_DATABASE", str(default_db)),
    )

    if test_config:
        app.config.update(test_config)

    Path(app.instance_path).mkdir(parents=True, exist_ok=True)
    app.teardown_appcontext(close_db)
    app.register_blueprint(api)
    register_commands(app)

    @app.after_request
    def add_local_dev_cors_headers(response):
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

    return app
