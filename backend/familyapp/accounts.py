from __future__ import annotations

import hashlib
import secrets
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any

from flask import g

from werkzeug.security import check_password_hash, generate_password_hash

from .domain import (
    AuthError,
    DomainError,
    Member,
    PermissionDenied,
    normalize_login,
    validate_password,
    validate_role,
)
from .persistence import get_db, now_iso, validate_member_icon, family_id

MEMBER_COLUMNS = "m.id, m.name, m.icon, m.role, m.family_id, m.user_id, u.login, u.password_hash, m.created_at, m.updated_at"
MEMBER_FROM = "members m LEFT JOIN users u ON u.id = m.user_id"


def create_member(
    name: str,
    icon: str,
    role: str,
    actor_id: int | None,
    login: str | None = None,
    password: str | None = None,
) -> dict[str, Any]:
    cleaned_name = clean_name(name)
    cleaned_icon = validate_member_icon(icon)
    cleaned_role = validate_role(role)
    has_login = bool((login or "").strip())
    if has_login != bool(password):
        raise DomainError("login and password must be provided together")

    if has_login:
        raise DomainError("use an invitation to link an account")
    db = get_db()
    timestamp = now_iso()
    cursor = db.execute(
        """
        INSERT INTO members (name, icon, role, created_by_member_id, created_at, updated_at, family_id)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (cleaned_name, cleaned_icon, cleaned_role, actor_id, timestamp, timestamp, family_id()),
    )
    member_id = int(cursor.lastrowid)
    db.commit()
    return get_member(member_id)


def update_member(member_id: int, name: str, icon: str) -> dict[str, Any]:
    get_member(member_id)
    db = get_db()
    db.execute(
        "UPDATE members SET name = ?, icon = ?, updated_at = ? WHERE id = ?",
        (clean_name(name), validate_member_icon(icon), now_iso(), member_id),
    )
    db.commit()
    return get_member(member_id)


def set_credentials(
    member_id: int,
    login: str,
    password: str,
    keep_session_id: int | None = None,
) -> dict[str, Any]:
    """Only the account owner can change their credentials."""
    member = get_member(member_id)
    if member["user_id"] != g.user_id:
        raise PermissionDenied("only account owner may change credentials")
    cleaned_login = normalize_login(login)
    validate_password(password)
    db = get_db()
    taken = db.execute("SELECT id FROM users WHERE login = ? AND id != ?", (cleaned_login, g.user_id)).fetchone()
    if taken:
        raise DomainError("login is already taken")
    db.execute("UPDATE users SET login = ?, password_hash = ? WHERE id = ?",
               (cleaned_login, generate_password_hash(password), g.user_id))
    db.execute("UPDATE user_sessions SET revoked_at = ? WHERE user_id = ? AND id IS NOT ?",
               (now_iso(), g.user_id, keep_session_id))
    db.commit()
    return get_member(member_id)


def register(name: str, login_value: str, password: str):
    name = clean_name(name)
    login_value = normalize_login(login_value)
    validate_password(password)
    db = get_db()
    try:
        cursor = db.execute("INSERT INTO users(name, login, password_hash, created_at) VALUES (?, ?, ?, ?)",
                            (name, login_value, generate_password_hash(password), now_iso()))
    except sqlite3.IntegrityError as exc:
        db.rollback()
        raise DomainError("login is already taken") from exc
    db.commit()
    user_id = int(cursor.lastrowid)
    return start_session_for(user_id), user_id


def login(login_value: str, password: str):
    row = get_db().execute("SELECT * FROM users WHERE login = ?", ((login_value or "").strip().lower(),)).fetchone()
    if not row or not check_password_hash(row["password_hash"], password or ""):
        raise AuthError("invalid login or password")
    return start_session_for(row["id"]), row["id"]


def start_session_for(user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    timestamp = now_iso()
    db = get_db()
    families = db.execute("SELECT family_id FROM members WHERE user_id = ?", (user_id,)).fetchall()
    selected = families[0]["family_id"] if len(families) == 1 else None
    db.execute("INSERT INTO user_sessions(user_id, family_id, token_hash, created_at, last_used_at) VALUES (?, ?, ?, ?, ?)",
               (user_id, selected, hash_token(token), timestamp, timestamp))
    db.commit()
    return token


def authenticate(token: str):
    db = get_db()
    row = db.execute("SELECT * FROM user_sessions WHERE token_hash = ? AND revoked_at IS NULL", (hash_token(token),)).fetchone()
    if not row:
        raise AuthError("authentication required")
    g.user_id = row["user_id"]
    g.family_id = row["family_id"]
    member_row = db.execute(f"SELECT {MEMBER_COLUMNS} FROM {MEMBER_FROM} WHERE m.user_id = ? AND m.family_id = ?",
                            (g.user_id, g.family_id)).fetchone()
    member = None
    if member_row:
        member = Member(id=member_row["id"], name=member_row["name"], role=member_row["role"], icon=member_row["icon"], login=member_row["login"])
    else:
        g.family_id = None
    db.execute("UPDATE user_sessions SET last_used_at = ? WHERE id = ?", (now_iso(), row["id"]))
    db.commit()
    return member, row["id"]


def account_state(user_id: int):
    db = get_db()
    user = dict(db.execute("SELECT id, name, login FROM users WHERE id = ?", (user_id,)).fetchone())
    families = [dict(row) for row in db.execute("SELECT f.id, f.name, m.role FROM families f JOIN members m ON m.family_id = f.id WHERE m.user_id = ? ORDER BY f.id", (user_id,))]
    member = get_member(g.member.id) if getattr(g, "member", None) else None
    return {"user": user, "families": families, "member": member, "family_id": getattr(g, "family_id", None)}


def select_family(selected: int):
    db = get_db()
    row = db.execute("SELECT id FROM members WHERE user_id = ? AND family_id = ?", (g.user_id, selected)).fetchone()
    if not row:
        raise PermissionDenied("family access denied")
    db.execute("UPDATE user_sessions SET family_id = ? WHERE id = ?", (selected, g.session_id))
    db.commit()
    g.family_id = selected
    data = get_member(row["id"])
    g.member = Member(id=data["id"], name=data["name"], role=data["role"], icon=data["icon"], login=data["login"])
    return account_state(g.user_id)


def create_family(name: str):
    db = get_db()
    timestamp = now_iso()
    cursor = db.execute("INSERT INTO families(name, created_at) VALUES (?, ?)", (clean_name(name), timestamp))
    selected = cursor.lastrowid
    user = db.execute("SELECT name FROM users WHERE id = ?", (g.user_id,)).fetchone()
    db.execute("INSERT INTO members(name, role, icon, family_id, user_id, created_at, updated_at) VALUES (?, 'parent', 'star', ?, ?, ?, ?)",
               (user["name"], selected, g.user_id, timestamp, timestamp))
    db.commit()
    return select_family(selected)


def create_invitation(role: str, member_id=None):
    role = validate_role(role)
    if member_id is not None:
        member = get_member(member_id)
        if member["user_id"] is not None:
            raise DomainError("member already has an account")
        role = member["role"]
    code = secrets.token_urlsafe(24)
    expires = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    db = get_db()
    db.execute("INSERT INTO invitations(family_id, member_id, role, token_hash, created_by_member_id, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
               (family_id(), member_id, role, hash_token(code), g.member.id, expires))
    db.commit()
    return {"code": code, "expires_at": expires, "role": role}


def accept_invitation(code: str):
    db = get_db()
    # Serialize acceptance so a code cannot be consumed by two users.
    db.execute("BEGIN IMMEDIATE")
    try:
        invitation = db.execute("SELECT * FROM invitations WHERE token_hash = ? AND used_at IS NULL AND expires_at > ?",
                                (hash_token((code or "").strip()), now_iso())).fetchone()
        if not invitation:
            raise DomainError("invitation invalid or expired")
        selected = invitation["family_id"]
        if db.execute("SELECT 1 FROM members WHERE user_id = ? AND family_id = ?", (g.user_id, selected)).fetchone():
            raise DomainError("already a family member")
        timestamp = now_iso()
        if invitation["member_id"] is not None:
            cursor = db.execute("UPDATE members SET user_id = ?, updated_at = ? WHERE id = ? AND family_id = ? AND user_id IS NULL",
                                (g.user_id, timestamp, invitation["member_id"], selected))
            if cursor.rowcount != 1:
                raise DomainError("member already has an account")
        else:
            user = db.execute("SELECT name FROM users WHERE id = ?", (g.user_id,)).fetchone()
            db.execute("INSERT INTO members(name, role, icon, family_id, user_id, created_by_member_id, created_at, updated_at) VALUES (?, ?, 'star', ?, ?, ?, ?, ?)",
                       (user["name"], invitation["role"], selected, g.user_id, invitation["created_by_member_id"], timestamp, timestamp))
        db.execute("UPDATE invitations SET used_at = ?, used_by_user_id = ? WHERE id = ?", (timestamp, g.user_id, invitation["id"]))
        db.commit()
    except Exception:
        db.rollback()
        raise
    return select_family(selected)


def revoke_session(session_id: int) -> None:
    db = get_db()
    db.execute(
        "UPDATE user_sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL",
        (now_iso(), session_id),
    )
    db.commit()


def list_members() -> list[dict[str, Any]]:
    rows = get_db().execute(
        f"""
        SELECT {MEMBER_COLUMNS}
        FROM {MEMBER_FROM}
        WHERE m.family_id = ?
        ORDER BY CASE role WHEN 'parent' THEN 0 ELSE 1 END, m.name COLLATE NOCASE
        """,
        (family_id(),),
    ).fetchall()
    return [serialize_member(row) for row in rows]


def get_member(member_id: int) -> dict[str, Any]:
    row = get_db().execute(
        f"SELECT {MEMBER_COLUMNS} FROM {MEMBER_FROM} WHERE m.id = ? AND m.family_id = ?",
        (member_id, family_id()),
    ).fetchone()
    if not row:
        raise DomainError("member not found")
    return serialize_member(row)


def clean_name(name: str) -> str:
    cleaned = (name or "").strip()
    if not cleaned:
        raise DomainError("name is required")
    return cleaned


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def serialize_member(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "family_id": row["family_id"],
        "name": row["name"],
        "icon": row["icon"],
        "role": row["role"],
        "login": row["login"],
        "has_account": row["password_hash"] is not None,
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }
