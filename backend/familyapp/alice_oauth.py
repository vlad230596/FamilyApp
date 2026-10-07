"""A single confidential OAuth client for Alice, with family-scoped read access."""
from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone

from flask import current_app, g
from werkzeug.security import check_password_hash

from .accounts import hash_token
from .persistence import get_db, now_iso

SCOPE = "restrictions:read"
ACCESS_SECONDS = 3600
REFRESH_SECONDS = 90 * 86400


def init_alice():
    get_db().executescript("""
        CREATE TABLE IF NOT EXISTS alice_grants (
            id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL, family_id INTEGER NOT NULL,
            client_id TEXT NOT NULL, credential_hash TEXT NOT NULL,
            created_at TEXT NOT NULL, revoked_at TEXT
        );
        CREATE TABLE IF NOT EXISTS alice_codes (
            code_hash TEXT PRIMARY KEY, grant_id INTEGER NOT NULL,
            redirect_uri TEXT NOT NULL, expires_at TEXT NOT NULL, used_at TEXT
        );
        CREATE TABLE IF NOT EXISTS alice_tokens (
            access_hash TEXT PRIMARY KEY, refresh_hash TEXT UNIQUE NOT NULL,
            grant_id INTEGER NOT NULL, access_expires_at TEXT NOT NULL,
            refresh_expires_at TEXT NOT NULL, replaced_at TEXT
        );
        CREATE TABLE IF NOT EXISTS alice_rate_limits (
            key TEXT PRIMARY KEY, attempts INTEGER NOT NULL, resets_at TEXT NOT NULL
        );
    """)
    get_db().commit()


def configured():
    return all(current_app.config.get(key) for key in
               ("ALICE_CLIENT_ID", "ALICE_CLIENT_SECRET", "ALICE_COOKIE_SECRET"))


def expires(seconds):
    return (datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat()


def consume_rate_limit(key, limit=10, seconds=60):
    """Persist limits across workers; never store passwords or raw client addresses."""
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        db.execute("DELETE FROM alice_rate_limits WHERE resets_at <= ?", (now_iso(),))
        db.execute("INSERT OR IGNORE INTO alice_rate_limits VALUES (?, 0, ?)",
                   (hash_token(key), expires(seconds)))
        db.execute("UPDATE alice_rate_limits SET attempts = attempts + 1 WHERE key = ?",
                   (hash_token(key),))
        count = db.execute("SELECT attempts FROM alice_rate_limits WHERE key = ?",
                           (hash_token(key),)).fetchone()[0]
    return count <= limit


def parent_families(user_id):
    return [dict(row) for row in get_db().execute(
        "SELECT f.id, f.name FROM families f JOIN members m ON m.family_id = f.id "
        "WHERE m.user_id = ? AND m.role = 'parent' ORDER BY f.id", (user_id,))]


def login_parent(login, password):
    row = get_db().execute("SELECT * FROM users WHERE login = ?",
                           (login.strip().lower(),)).fetchone()
    # Perform a password hash check for unknown logins as well.
    if not check_password_hash(row["password_hash"] if row else current_app.config["ALICE_DUMMY_HASH"], password):
        return None
    if not row or not parent_families(row["id"]):
        return None
    return {"user_id": row["id"], "credential_hash": hash_token(row["password_hash"])}


def valid_browser_user(flow):
    row = get_db().execute("SELECT password_hash FROM users WHERE id = ?",
                           (flow.get("user_id"),)).fetchone()
    return bool(row and secrets.compare_digest(hash_token(row["password_hash"]),
                                               flow.get("credential_hash", "")))


def issue_code(flow, family_id):
    if not valid_browser_user(flow) or family_id not in {f["id"] for f in parent_families(flow["user_id"])}:
        return None
    code = secrets.token_urlsafe(32)
    db = get_db()
    with db:
        cursor = db.execute(
            "INSERT INTO alice_grants(user_id, family_id, client_id, credential_hash, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            (flow["user_id"], family_id, flow["client_id"], flow["credential_hash"], now_iso()))
        db.execute("INSERT INTO alice_codes VALUES (?, ?, ?, ?, NULL)",
                   (hash_token(code), cursor.lastrowid, flow["redirect_uri"], expires(300)))
    return code


def valid_grant(grant_id):
    row = get_db().execute(
        "SELECT a.*, u.password_hash FROM alice_grants a JOIN users u ON u.id = a.user_id "
        "JOIN members m ON m.user_id = a.user_id AND m.family_id = a.family_id "
        "WHERE a.id = ? AND a.revoked_at IS NULL AND m.role = 'parent' AND a.client_id = ?",
        (grant_id, current_app.config["ALICE_CLIENT_ID"])).fetchone()
    if row and secrets.compare_digest(hash_token(row["password_hash"]), row["credential_hash"]):
        return row
    return None


def exchange_token(payload):
    """Consume codes/refresh tokens atomically; rotated access tokens stay valid until expiry."""
    db = get_db()
    db.execute("BEGIN IMMEDIATE")
    try:
        if payload.get("grant_type") == "authorization_code":
            row = db.execute("SELECT * FROM alice_codes WHERE code_hash = ? AND used_at IS NULL AND expires_at > ?",
                             (hash_token(payload.get("code", "")), now_iso())).fetchone()
            if not row or row["redirect_uri"] != payload.get("redirect_uri"):
                db.rollback()
                return None
            grant_id = row["grant_id"]
            if not valid_grant(grant_id):
                db.rollback()
                return None
            db.execute("UPDATE alice_codes SET used_at = ? WHERE code_hash = ?", (now_iso(), row["code_hash"]))
            refresh_expiry = expires(REFRESH_SECONDS)
        else:
            row = db.execute("SELECT * FROM alice_tokens WHERE refresh_hash = ? AND replaced_at IS NULL AND refresh_expires_at > ?",
                             (hash_token(payload.get("refresh_token", "")), now_iso())).fetchone()
            if not row or not valid_grant(row["grant_id"]):
                db.rollback()
                return None
            grant_id = row["grant_id"]
            refresh_expiry = row["refresh_expires_at"]
            db.execute("UPDATE alice_tokens SET replaced_at = ? WHERE access_hash = ?", (now_iso(), row["access_hash"]))
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        db.execute("INSERT INTO alice_tokens VALUES (?, ?, ?, ?, ?, NULL)",
                   (hash_token(access), hash_token(refresh), grant_id, expires(ACCESS_SECONDS), refresh_expiry))
        db.commit()
        return {"access_token": access, "refresh_token": refresh, "token_type": "Bearer",
                "expires_in": ACCESS_SECONDS, "scope": SCOPE}
    except Exception:
        db.rollback()
        raise


def authenticate_alice(token):
    row = get_db().execute("SELECT grant_id FROM alice_tokens WHERE access_hash = ? AND access_expires_at > ?",
                           (hash_token(token), now_iso())).fetchone()
    grant = valid_grant(row["grant_id"]) if row else None
    if not grant:
        return False
    g.family_id = grant["family_id"]
    g.user_id = grant["user_id"]
    g.alice_grant_id = grant["id"]
    return True


def connections(user_id):
    return [dict(row) for row in get_db().execute(
        "SELECT a.id, f.name, a.created_at FROM alice_grants a JOIN families f ON f.id = a.family_id "
        "WHERE a.user_id = ? AND a.revoked_at IS NULL AND EXISTS "
        "(SELECT 1 FROM alice_tokens t WHERE t.grant_id = a.id) ORDER BY a.id DESC", (user_id,))]


def revoke_connection(user_id, grant_id):
    db = get_db()
    db.execute("UPDATE alice_grants SET revoked_at = ? WHERE user_id = ? AND id = ?",
               (now_iso(), user_id, grant_id))
    db.commit()
