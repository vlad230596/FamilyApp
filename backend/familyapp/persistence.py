from __future__ import annotations

import sqlite3
from datetime import date, datetime, timezone
from typing import Any

from flask import current_app, g

from .domain import ACTIVE, CANCELLED, DomainError, effective_status, ensure_active


def get_db() -> sqlite3.Connection:
    if "db" not in g:
        g.db = sqlite3.connect(current_app.config["DATABASE"])
        g.db.row_factory = sqlite3.Row
    return g.db


def close_db(_error: Exception | None = None) -> None:
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db() -> None:
    db = get_db()
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS parent_admins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS children (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_by_admin_id INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (created_by_admin_id) REFERENCES parent_admins (id)
        );

        CREATE TABLE IF NOT EXISTS restrictions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            child_id INTEGER NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            reason TEXT NOT NULL,
            status TEXT NOT NULL,
            created_by_admin_id INTEGER NOT NULL,
            updated_by_admin_id INTEGER NOT NULL,
            cancelled_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (child_id) REFERENCES children (id),
            FOREIGN KEY (created_by_admin_id) REFERENCES parent_admins (id),
            FOREIGN KEY (updated_by_admin_id) REFERENCES parent_admins (id)
        );

        CREATE TABLE IF NOT EXISTS restriction_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            restriction_id INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            old_end_date TEXT,
            new_end_date TEXT,
            actor_admin_id INTEGER NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (restriction_id) REFERENCES restrictions (id),
            FOREIGN KEY (actor_admin_id) REFERENCES parent_admins (id)
        );
        """
    )
    ensure_default_admin()
    db.commit()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_default_admin() -> int:
    db = get_db()
    row = db.execute("SELECT id FROM parent_admins ORDER BY id LIMIT 1").fetchone()
    if row:
        return int(row["id"])

    cursor = db.execute(
        "INSERT INTO parent_admins (name, created_at) VALUES (?, ?)",
        ("Parent Admin", now_iso()),
    )
    return int(cursor.lastrowid)


def list_children() -> list[dict[str, Any]]:
    rows = get_db().execute(
        "SELECT id, name, created_at FROM children ORDER BY name COLLATE NOCASE"
    ).fetchall()
    return [dict(row) for row in rows]


def create_child(name: str, admin_id: int | None = None) -> dict[str, Any]:
    cleaned = (name or "").strip()
    if not cleaned:
        raise DomainError("name is required")

    db = get_db()
    admin_id = admin_id or ensure_default_admin()
    cursor = db.execute(
        """
        INSERT INTO children (name, created_by_admin_id, created_at)
        VALUES (?, ?, ?)
        """,
        (cleaned, admin_id, now_iso()),
    )
    db.commit()
    return get_child(int(cursor.lastrowid))


def get_child(child_id: int) -> dict[str, Any]:
    row = get_db().execute(
        "SELECT id, name, created_at FROM children WHERE id = ?",
        (child_id,),
    ).fetchone()
    if not row:
        raise DomainError("child not found")
    return dict(row)


def create_restriction(
    child_id: int,
    start_date: date,
    end_date: date,
    reason: str,
    admin_id: int | None = None,
) -> dict[str, Any]:
    get_child(child_id)
    cleaned_reason = (reason or "").strip()
    if not cleaned_reason:
        raise DomainError("reason is required")

    db = get_db()
    admin_id = admin_id or ensure_default_admin()
    timestamp = now_iso()
    cursor = db.execute(
        """
        INSERT INTO restrictions (
            child_id, start_date, end_date, reason, status,
            created_by_admin_id, updated_by_admin_id, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            child_id,
            start_date.isoformat(),
            end_date.isoformat(),
            cleaned_reason,
            ACTIVE,
            admin_id,
            admin_id,
            timestamp,
            timestamp,
        ),
    )
    restriction_id = int(cursor.lastrowid)
    add_event(restriction_id, "created", None, end_date.isoformat(), admin_id, None)
    db.commit()
    return get_restriction(restriction_id)


def list_restrictions(child_id: int | None = None) -> list[dict[str, Any]]:
    params: list[Any] = []
    where = ""
    if child_id is not None:
        where = "WHERE r.child_id = ?"
        params.append(child_id)

    rows = get_db().execute(
        f"""
        SELECT r.*, c.name AS child_name
        FROM restrictions r
        JOIN children c ON c.id = r.child_id
        {where}
        ORDER BY r.end_date DESC, r.id DESC
        """,
        params,
    ).fetchall()
    return [serialize_restriction(row) for row in rows]


def get_restriction(restriction_id: int) -> dict[str, Any]:
    row = get_db().execute(
        """
        SELECT r.*, c.name AS child_name
        FROM restrictions r
        JOIN children c ON c.id = r.child_id
        WHERE r.id = ?
        """,
        (restriction_id,),
    ).fetchone()
    if not row:
        raise DomainError("restriction not found")
    return serialize_restriction(row)


def extend_restriction(
    restriction_id: int,
    new_end_date: date,
    admin_id: int | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    db = get_db()
    row = db.execute("SELECT * FROM restrictions WHERE id = ?", (restriction_id,)).fetchone()
    if not row:
        raise DomainError("restriction not found")

    old_end_date = date.fromisoformat(row["end_date"])
    ensure_active(row["status"], old_end_date)
    if new_end_date <= old_end_date:
        raise DomainError("new_end_date must be after current end_date")

    admin_id = admin_id or ensure_default_admin()
    timestamp = now_iso()
    db.execute(
        """
        UPDATE restrictions
        SET end_date = ?, updated_by_admin_id = ?, updated_at = ?
        WHERE id = ?
        """,
        (new_end_date.isoformat(), admin_id, timestamp, restriction_id),
    )
    add_event(
        restriction_id,
        "extended",
        old_end_date.isoformat(),
        new_end_date.isoformat(),
        admin_id,
        note,
    )
    db.commit()
    return get_restriction(restriction_id)


def cancel_restriction(
    restriction_id: int,
    admin_id: int | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    db = get_db()
    row = db.execute("SELECT * FROM restrictions WHERE id = ?", (restriction_id,)).fetchone()
    if not row:
        raise DomainError("restriction not found")

    end_date = date.fromisoformat(row["end_date"])
    ensure_active(row["status"], end_date)

    admin_id = admin_id or ensure_default_admin()
    timestamp = now_iso()
    db.execute(
        """
        UPDATE restrictions
        SET status = ?, updated_by_admin_id = ?, updated_at = ?, cancelled_at = ?
        WHERE id = ?
        """,
        (CANCELLED, admin_id, timestamp, timestamp, restriction_id),
    )
    add_event(restriction_id, "cancelled", row["end_date"], row["end_date"], admin_id, note)
    db.commit()
    return get_restriction(restriction_id)


def add_event(
    restriction_id: int,
    event_type: str,
    old_end_date: str | None,
    new_end_date: str | None,
    actor_admin_id: int,
    note: str | None,
) -> None:
    get_db().execute(
        """
        INSERT INTO restriction_events (
            restriction_id, event_type, old_end_date, new_end_date,
            actor_admin_id, note, created_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (restriction_id, event_type, old_end_date, new_end_date, actor_admin_id, note, now_iso()),
    )


def serialize_restriction(row: sqlite3.Row) -> dict[str, Any]:
    end_date = date.fromisoformat(row["end_date"])
    return {
        "id": row["id"],
        "child_id": row["child_id"],
        "child_name": row["child_name"],
        "start_date": row["start_date"],
        "end_date": row["end_date"],
        "reason": row["reason"],
        "status": effective_status(row["status"], end_date),
        "stored_status": row["status"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "cancelled_at": row["cancelled_at"],
    }
