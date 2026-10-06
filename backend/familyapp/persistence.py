from __future__ import annotations

import sqlite3
from datetime import date, datetime, timezone
from typing import Any

from flask import current_app, g

from .domain import (
    ACTIVE,
    CANCELLED,
    ROLE_CHILD,
    ROLE_PARENT,
    DomainError,
    effective_status,
    ensure_active,
    validate_hex_color,
)


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
        CREATE TABLE IF NOT EXISTS members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            icon TEXT NOT NULL DEFAULT 'star',
            role TEXT NOT NULL,
            login TEXT UNIQUE,
            password_hash TEXT,
            created_by_member_id INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (created_by_member_id) REFERENCES members (id)
        );

        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            member_id INTEGER NOT NULL,
            token_hash TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL,
            last_used_at TEXT NOT NULL,
            revoked_at TEXT,
            FOREIGN KEY (member_id) REFERENCES members (id)
        );

        CREATE TABLE IF NOT EXISTS restriction_types (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        -- The *_admin_id column names predate the members table; they now hold
        -- the id of the parent member who made the change.
        CREATE TABLE IF NOT EXISTS restrictions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            child_id INTEGER NOT NULL,
            restriction_type_id INTEGER,
            custom_type_name TEXT,
            color TEXT NOT NULL DEFAULT '#607D8B',
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            reason TEXT NOT NULL,
            status TEXT NOT NULL,
            created_by_admin_id INTEGER NOT NULL,
            updated_by_admin_id INTEGER NOT NULL,
            cancelled_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (child_id) REFERENCES members (id),
            FOREIGN KEY (restriction_type_id) REFERENCES restriction_types (id),
            FOREIGN KEY (created_by_admin_id) REFERENCES members (id),
            FOREIGN KEY (updated_by_admin_id) REFERENCES members (id)
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
            FOREIGN KEY (actor_admin_id) REFERENCES members (id)
        );
        """
    )
    if table_exists("children"):
        ensure_column("children", "icon", "TEXT NOT NULL DEFAULT 'star'")
    ensure_column("restrictions", "restriction_type_id", "INTEGER")
    ensure_column("restrictions", "custom_type_name", "TEXT")
    ensure_column("restrictions", "color", "TEXT NOT NULL DEFAULT '#607D8B'")
    migrate_legacy_people()
    migrate_families()
    db.commit()


def table_exists(table: str) -> bool:
    row = get_db().execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (table,),
    ).fetchone()
    return row is not None


def ensure_column(table: str, column: str, definition: str) -> None:
    db = get_db()
    columns = db.execute(f"PRAGMA table_info({table})").fetchall()
    if column not in {row["name"] for row in columns}:
        db.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def migrate_legacy_people() -> None:
    """Move pre-accounts `children` and `parent_admins` rows into `members`.

    Children keep their ids so existing restrictions stay attached. Parent
    admins get new ids, and audit columns are remapped to them. The legacy
    tables are left in place untouched.
    """
    db = get_db()
    if db.execute("SELECT 1 FROM members LIMIT 1").fetchone():
        return

    timestamp = now_iso()
    if table_exists("children"):
        db.execute(
            """
            INSERT INTO members (id, name, icon, role, created_at, updated_at)
            SELECT id, name, icon, ?, created_at, ?
            FROM children
            ORDER BY id
            """,
            (ROLE_CHILD, timestamp),
        )

    if not table_exists("parent_admins"):
        return

    admin_ids: dict[int, int] = {}
    admins = db.execute("SELECT id, name, created_at FROM parent_admins ORDER BY id").fetchall()
    for row in admins:
        cursor = db.execute(
            """
            INSERT INTO members (name, icon, role, created_at, updated_at)
            VALUES (?, 'star', ?, ?, ?)
            """,
            (row["name"], ROLE_PARENT, row["created_at"], timestamp),
        )
        admin_ids[int(row["id"])] = int(cursor.lastrowid)

    # Remap through negative ids so an old id never collides with a new one.
    audit_columns = [
        ("restrictions", "created_by_admin_id"),
        ("restrictions", "updated_by_admin_id"),
        ("restriction_events", "actor_admin_id"),
    ]
    for table, column in audit_columns:
        for old_id, new_id in admin_ids.items():
            db.execute(
                f"UPDATE {table} SET {column} = ? WHERE {column} = ?",
                (-new_id, old_id),
            )
        db.execute(f"UPDATE {table} SET {column} = -{column} WHERE {column} < 0")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def list_children() -> list[dict[str, Any]]:
    rows = get_db().execute(
        """
        SELECT id, name, icon, created_at
        FROM members
        WHERE role = ? AND family_id = ?
        ORDER BY name COLLATE NOCASE
        """,
        (ROLE_CHILD, family_id()),
    ).fetchall()
    return [dict(row) for row in rows]


def get_child(child_id: int) -> dict[str, Any]:
    row = get_db().execute(
        "SELECT id, name, icon, created_at FROM members WHERE id = ? AND role = ? AND family_id = ?",
        (child_id, ROLE_CHILD, family_id()),
    ).fetchone()
    if not row:
        raise DomainError("child not found")
    return dict(row)


def validate_member_icon(value: str) -> str:
    cleaned = (value or "star").strip()
    allowed = {
        "star",
        "dragon",
        "pet",
        "bird",
        "butterfly",
        "bug",
        "forest",
        "flower",
        "leaf",
        "eco",
        "park",
        "rocket",
        "sparkles",
        "gamepad",
        "heart",
        "school",
        "bolt",
        "puzzle",
    }
    if cleaned not in allowed:
        raise DomainError("icon is not supported")
    return cleaned


def list_restriction_types(include_archived: bool = False) -> list[dict[str, Any]]:
    where = "WHERE family_id = ?" + ("" if include_archived else " AND archived = 0")
    rows = get_db().execute(
        f"""
        SELECT id, name, color, archived, created_at, updated_at
        FROM restriction_types
        {where}
        ORDER BY archived, name COLLATE NOCASE
        """,
        (family_id(),),
    ).fetchall()
    return [serialize_restriction_type(row) for row in rows]


def create_restriction_type(name: str, color: str) -> dict[str, Any]:
    cleaned_name = (name or "").strip()
    if not cleaned_name:
        raise DomainError("name is required")
    cleaned_color = validate_hex_color(color)

    db = get_db()
    timestamp = now_iso()
    cursor = db.execute(
        """
        INSERT INTO restriction_types (name, color, archived, created_at, updated_at, family_id)
        VALUES (?, ?, 0, ?, ?, ?)
        """,
        (cleaned_name, cleaned_color, timestamp, timestamp, family_id()),
    )
    db.commit()
    return get_restriction_type(int(cursor.lastrowid), include_archived=True)


def archive_restriction_type(restriction_type_id: int) -> dict[str, Any]:
    get_restriction_type(restriction_type_id, include_archived=True)
    db = get_db()
    db.execute(
        "UPDATE restriction_types SET archived = 1, updated_at = ? WHERE id = ?",
        (now_iso(), restriction_type_id),
    )
    db.commit()
    return get_restriction_type(restriction_type_id, include_archived=True)


def get_restriction_type(
    restriction_type_id: int,
    include_archived: bool = False,
) -> dict[str, Any]:
    row = get_db().execute(
        """
        SELECT id, name, color, archived, created_at, updated_at
        FROM restriction_types
        WHERE id = ? AND family_id = ?
        """,
        (restriction_type_id, family_id()),
    ).fetchone()
    if not row or (row["archived"] and not include_archived):
        raise DomainError("restriction type not found")
    return serialize_restriction_type(row)


def create_restriction(
    child_id: int,
    start_date: date,
    end_date: date,
    reason: str,
    restriction_type_id: int | None = None,
    custom_type_name: str | None = None,
    color: str | None = None,
    *,
    admin_id: int,
) -> dict[str, Any]:
    get_child(child_id)
    cleaned_reason = (reason or "").strip()
    cleaned_custom_type_name = (custom_type_name or "").strip() or None
    if restriction_type_id is None and not cleaned_custom_type_name:
        raise DomainError("restriction_type_id or custom_type_name is required")
    if restriction_type_id is not None and cleaned_custom_type_name:
        raise DomainError("use either restriction_type_id or custom_type_name")

    if restriction_type_id is not None:
        restriction_type = get_restriction_type(restriction_type_id)
        resolved_color = restriction_type["color"]
    else:
        resolved_color = validate_hex_color(color or "#607D8B")

    db = get_db()
    timestamp = now_iso()
    cursor = db.execute(
        """
        INSERT INTO restrictions (
            child_id, restriction_type_id, custom_type_name, color,
            start_date, end_date, reason, status,
            created_by_admin_id, updated_by_admin_id, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            child_id,
            restriction_type_id,
            cleaned_custom_type_name,
            resolved_color,
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
    params: list[Any] = [family_id()]
    where = "WHERE c.family_id = ?"
    if child_id is not None:
        where += " AND r.child_id = ?"
        params.append(child_id)

    rows = get_db().execute(
        f"""
        SELECT r.*, c.name AS child_name, c.icon AS child_icon,
               rt.name AS restriction_type_name
        FROM restrictions r
        JOIN members c ON c.id = r.child_id
        LEFT JOIN restriction_types rt ON rt.id = r.restriction_type_id
        {where}
        ORDER BY r.end_date DESC, r.id DESC
        """,
        params,
    ).fetchall()
    return [serialize_restriction(row) for row in rows]


def get_restriction(restriction_id: int) -> dict[str, Any]:
    row = get_db().execute(
        """
        SELECT r.*, c.name AS child_name, c.icon AS child_icon,
               rt.name AS restriction_type_name
        FROM restrictions r
        JOIN members c ON c.id = r.child_id
        LEFT JOIN restriction_types rt ON rt.id = r.restriction_type_id
        WHERE r.id = ? AND c.family_id = ?
        """,
        (restriction_id, family_id()),
    ).fetchone()
    if not row:
        raise DomainError("restriction not found")
    return serialize_restriction(row)


def list_today_restrictions(
    today: date | None = None,
    child_id: int | None = None,
) -> list[dict[str, Any]]:
    today = today or date.today()
    return list_restrictions_for_range(today, today, child_id)


def list_restrictions_for_range(
    start_date: date,
    end_date: date,
    child_id: int | None = None,
) -> list[dict[str, Any]]:
    params: list[Any] = [ACTIVE, end_date.isoformat(), start_date.isoformat(), family_id()]
    child_filter = ""
    if child_id is not None:
        child_filter = "AND r.child_id = ?"
        params.append(child_id)

    rows = get_db().execute(
        f"""
        SELECT r.*, c.name AS child_name, c.icon AS child_icon,
               rt.name AS restriction_type_name
        FROM restrictions r
        JOIN members c ON c.id = r.child_id
        LEFT JOIN restriction_types rt ON rt.id = r.restriction_type_id
        WHERE r.status = ?
          AND r.start_date <= ?
          AND r.end_date >= ?
          AND c.family_id = ?
          {child_filter}
        ORDER BY r.start_date, c.name COLLATE NOCASE, r.id
        """,
        params,
    ).fetchall()
    return [serialize_restriction(row) for row in rows]


def extend_restriction(
    restriction_id: int,
    new_end_date: date,
    *,
    admin_id: int,
    note: str | None = None,
) -> dict[str, Any]:
    get_restriction(restriction_id)
    db = get_db()
    row = db.execute("SELECT * FROM restrictions WHERE id = ?", (restriction_id,)).fetchone()
    if not row:
        raise DomainError("restriction not found")

    old_end_date = date.fromisoformat(row["end_date"])
    ensure_active(row["status"], old_end_date)
    if new_end_date <= old_end_date:
        raise DomainError("new_end_date must be after current end_date")

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
    *,
    admin_id: int,
    note: str | None = None,
) -> dict[str, Any]:
    get_restriction(restriction_id)
    db = get_db()
    row = db.execute("SELECT * FROM restrictions WHERE id = ?", (restriction_id,)).fetchone()
    if not row:
        raise DomainError("restriction not found")

    end_date = date.fromisoformat(row["end_date"])
    ensure_active(row["status"], end_date)

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
        "child_icon": row["child_icon"],
        "restriction_type_id": row["restriction_type_id"],
        "restriction_type_name": row["restriction_type_name"],
        "custom_type_name": row["custom_type_name"],
        "type_name": row["restriction_type_name"] or row["custom_type_name"],
        "color": row["color"],
        "start_date": row["start_date"],
        "end_date": row["end_date"],
        "reason": row["reason"],
        "status": effective_status(row["status"], end_date),
        "stored_status": row["status"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "cancelled_at": row["cancelled_at"],
    }


def serialize_restriction_type(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "name": row["name"],
        "color": row["color"],
        "archived": bool(row["archived"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def family_id() -> int:
    """Family context is established by the authenticated session."""
    value = getattr(g, "family_id", None)
    if value is None:
        from .domain import PermissionDenied
        raise PermissionDenied("family selection required")
    return value


def migrate_families() -> None:
    db = get_db()
    db.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            login TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS families (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS user_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL,
            family_id INTEGER, token_hash TEXT UNIQUE NOT NULL,
            created_at TEXT NOT NULL, last_used_at TEXT NOT NULL, revoked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS invitations (
            id INTEGER PRIMARY KEY AUTOINCREMENT, family_id INTEGER NOT NULL,
            member_id INTEGER, role TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
            created_by_member_id INTEGER NOT NULL, expires_at TEXT NOT NULL,
            used_by_user_id INTEGER, used_at TEXT
        );
    """)
    ensure_column("members", "family_id", "INTEGER")
    ensure_column("members", "user_id", "INTEGER")
    ensure_column("restriction_types", "family_id", "INTEGER")
    db.execute("CREATE UNIQUE INDEX IF NOT EXISTS member_user_family ON members(user_id, family_id)")
    rows = db.execute("SELECT * FROM members WHERE family_id IS NULL").fetchall()
    orphan_types = db.execute("SELECT 1 FROM restriction_types WHERE family_id IS NULL").fetchone()
    if not rows and not orphan_types:
        return
    cursor = db.execute("INSERT INTO families(name, created_at) VALUES (?, ?)", ("Семья", now_iso()))
    legacy_family = cursor.lastrowid
    for row in rows:
        user_id = None
        if row["password_hash"]:
            cursor = db.execute("INSERT INTO users(name, login, password_hash, created_at) VALUES (?, ?, ?, ?)",
                                (row["name"], row["login"], row["password_hash"], row["created_at"]))
            user_id = cursor.lastrowid
        db.execute("UPDATE members SET family_id = ?, user_id = ?, login = NULL, password_hash = NULL WHERE id = ?",
                   (legacy_family, user_id, row["id"]))
    db.execute("UPDATE restriction_types SET family_id = ? WHERE family_id IS NULL", (legacy_family,))
    db.execute("UPDATE sessions SET revoked_at = ? WHERE revoked_at IS NULL", (now_iso(),))
