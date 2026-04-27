from __future__ import annotations

import os
from pathlib import Path

from flask import Flask

from .persistence import close_db, init_db
from .routes import api


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

    with app.app_context():
        init_db()

    return app
