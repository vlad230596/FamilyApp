"""Private voice QA journal. Never persist protocol bodies or credentials."""
import json
import time
from datetime import datetime, timedelta, timezone

import click
from flask import current_app, g, request
from werkzeug.exceptions import HTTPException

from .persistence import get_db, now_iso


def init_journal():
    get_db().executescript("""
        CREATE TABLE IF NOT EXISTS alice_journal (
            id INTEGER PRIMARY KEY, created_at TEXT NOT NULL, family_id INTEGER,
            command TEXT, original_utterance TEXT, response_text TEXT,
            http_status INTEGER NOT NULL, outcome TEXT NOT NULL,
            end_session INTEGER, duration_ms INTEGER NOT NULL,
            review TEXT NOT NULL DEFAULT 'unreviewed', expected_response TEXT
        );
        CREATE INDEX IF NOT EXISTS alice_journal_created ON alice_journal(created_at);
    """)
    get_db().commit()


def before_webhook():
    if request.endpoint == "alice.webhook":
        g.alice_started = time.monotonic()


def record_response(response):
    if request.endpoint != "alice.webhook":
        return response
    try:
        payload = request.get_json(silent=True)
    except HTTPException:
        payload = None
    utterance = payload.get("request", {}) if isinstance(payload, dict) else {}
    utterance = utterance if isinstance(utterance, dict) else {}
    result = response.get_json(silent=True) or {}
    spoken = result.get("response", {})
    outcome = getattr(g, "alice_outcome", None) or result.get("error") or ("account_linking" if "start_account_linking" in result else "error")
    if response.status_code >= 500:
        outcome = "error"
    def bounded(value):
        return value[:2048] if isinstance(value, str) else None
    db = get_db()
    # The journal stores only an allowlist of utterance/answer fields, no tokens,
    # headers, session state, OAuth callbacks, IPs or user/device identifiers.
    db.execute("""INSERT INTO alice_journal
        (created_at, family_id, command, original_utterance, response_text,
         http_status, outcome, end_session, duration_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (now_iso(), getattr(g, "family_id", None), bounded(utterance.get("command")),
         bounded(utterance.get("original_utterance")), bounded(spoken.get("text")),
         response.status_code, outcome, spoken.get("end_session"),
         int((time.monotonic() - getattr(g, "alice_started", time.monotonic())) * 1000)))
    cutoff = datetime.now(timezone.utc) - timedelta(days=current_app.config["ALICE_JOURNAL_RETENTION_DAYS"])
    db.execute("DELETE FROM alice_journal WHERE created_at < ?", (cutoff.isoformat(),))
    db.commit()
    return response


def register_commands(app):
    @app.cli.command("alice-journal-export")
    @click.option("--family-id", type=int, required=True)
    @click.option("--review", type=click.Choice(["unreviewed", "correct", "incorrect", "all"]), default="all")
    @click.option("--output", type=click.Path(), required=True)
    def export(family_id, review, output):
        """Export private QA records as JSONL to an operator-chosen file."""
        rows = get_db().execute("SELECT * FROM alice_journal WHERE family_id = ? ORDER BY id", (family_id,))
        with open(output, "x", encoding="utf-8") as target:
            for row in rows:
                if review == "all" or row["review"] == review:
                    target.write(json.dumps(dict(row), ensure_ascii=False) + "\n")
        click.echo("Journal exported. Keep this file private; anonymize before adding examples to the repository.")

    @app.cli.command("alice-journal-review")
    @click.argument("entry_id", type=int)
    @click.option("--result", type=click.Choice(["correct", "incorrect"]), required=True)
    @click.option("--expected", default=None)
    def review(entry_id, result, expected):
        """Record manual QA; automatic handling does not prove correctness."""
        cursor = get_db().execute("UPDATE alice_journal SET review = ?, expected_response = ? WHERE id = ?", (result, expected, entry_id))
        if not cursor.rowcount:
            raise click.ClickException("Journal entry not found")
        get_db().commit()
        click.echo("Review saved.")
