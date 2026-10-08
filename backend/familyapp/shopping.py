"""Shared shopping list, urgency, purchases and scheduled returns."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from flask import g

from .domain import DomainError
from .persistence import family_id, get_db, now_iso

URGENCIES = ("background", "week", "urgent")


def utc_now():
    return datetime.now(timezone.utc)


def init_shopping():
    get_db().executescript("""
        CREATE TABLE IF NOT EXISTS shopping_items (
            id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL, name TEXT NOT NULL,
            normalized_name TEXT NOT NULL, urgency TEXT NOT NULL, category TEXT NOT NULL,
            created_by_member_id INTEGER NOT NULL, updated_by_member_id INTEGER NOT NULL,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL, urgency_since TEXT NOT NULL,
            UNIQUE(family_id, normalized_name)
        );
        CREATE TABLE IF NOT EXISTS shopping_purchases (
            id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL, name TEXT NOT NULL,
            normalized_name TEXT NOT NULL, urgency TEXT NOT NULL, category TEXT NOT NULL,
            bought_by_member_id INTEGER NOT NULL, bought_at TEXT NOT NULL,
            return_at TEXT, returned_at TEXT, return_cancelled_at TEXT
        );
        CREATE INDEX IF NOT EXISTS shopping_returns ON shopping_purchases(family_id, return_at);
    """)
    db = get_db()
    db.execute("CREATE TABLE IF NOT EXISTS shopping_lists (id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL, name TEXT NOT NULL, is_main INTEGER NOT NULL DEFAULT 0)")
    db.execute("CREATE UNIQUE INDEX IF NOT EXISTS shopping_main ON shopping_lists(family_id) WHERE is_main = 1")
    if 'list_id' not in [row['name'] for row in db.execute('PRAGMA table_info(shopping_items)')]:
        db.execute("INSERT INTO shopping_lists(family_id, name, is_main) SELECT id, 'Главный', 1 FROM families")
        db.execute("ALTER TABLE shopping_items RENAME TO shopping_items_legacy")
        db.execute("""CREATE TABLE shopping_items (
            id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL, list_id INTEGER NOT NULL,
            name TEXT NOT NULL, normalized_name TEXT NOT NULL, urgency TEXT NOT NULL, category TEXT NOT NULL,
            created_by_member_id INTEGER NOT NULL, updated_by_member_id INTEGER NOT NULL,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL, urgency_since TEXT NOT NULL,
            UNIQUE(list_id, normalized_name))""")
        db.execute("""INSERT INTO shopping_items SELECT i.id, i.family_id, l.id, i.name, i.normalized_name,
            i.urgency, i.category, i.created_by_member_id, i.updated_by_member_id, i.created_at,
            i.updated_at, i.urgency_since FROM shopping_items_legacy i JOIN shopping_lists l ON l.family_id = i.family_id""")
        db.execute("DROP TABLE shopping_items_legacy")
        db.execute("ALTER TABLE shopping_purchases ADD COLUMN list_id INTEGER")
        db.execute("UPDATE shopping_purchases SET list_id = (SELECT id FROM shopping_lists WHERE family_id = shopping_purchases.family_id AND is_main = 1)")
    db.commit()


def resolve_list(list_id=None):
    db = get_db()
    if list_id is None:
        row = db.execute("SELECT id FROM shopping_lists WHERE family_id = ? AND is_main = 1", (family_id(),)).fetchone()
        if row is None:
            return db.execute("INSERT INTO shopping_lists(family_id, name, is_main) VALUES (?, 'Главный', 1)", (family_id(),)).lastrowid
        return row['id']
    if type(list_id) is not int or db.execute("SELECT id FROM shopping_lists WHERE id = ? AND family_id = ?", (list_id, family_id())).fetchone() is None:
        raise DomainError("shopping list not found")
    return list_id


def save_list(payload, list_id=None):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    name = payload.get('name')
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80:
        raise DomainError("shopping list name must be 1-80 characters")
    main = payload.get('is_main', False)
    if type(main) is not bool:
        raise DomainError("invalid main shopping list")
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        resolve_list()
        if list_id is not None:
            resolve_list(list_id)
        if main:
            db.execute("UPDATE shopping_lists SET is_main = 0 WHERE family_id = ?", (family_id(),))
        if list_id is None:
            list_id = db.execute("INSERT INTO shopping_lists(family_id, name, is_main) VALUES (?, ?, ?)", (family_id(), name.strip(), int(main))).lastrowid
        else:
            db.execute("UPDATE shopping_lists SET name = ?, is_main = CASE WHEN ? THEN 1 ELSE is_main END WHERE id = ?", (name.strip(), main, list_id))
    return dict(db.execute("SELECT * FROM shopping_lists WHERE id = ?", (list_id,)).fetchone())


def validate(payload):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    name = payload.get("name")
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 200:
        raise DomainError("shopping name must be 1-200 characters")
    name = " ".join(name.split())
    urgency = payload.get("urgency", "week")
    if urgency not in URGENCIES:
        raise DomainError("invalid shopping urgency")
    category = payload.get("category", "")
    if not isinstance(category, str) or len(category.strip()) > 80:
        raise DomainError("shopping category must be up to 80 characters")
    return dict(name=name, normalized_name=name.casefold().replace("ё", "е"), urgency=urgency, category=category.strip())


def add(values, actor, timestamp, raise_duplicate=True):
    db = get_db()
    list_id = resolve_list(values.get("list_id"))
    existing = db.execute("SELECT * FROM shopping_items WHERE list_id = ? AND normalized_name = ?",
                          (list_id, values["normalized_name"])).fetchone()
    if existing:
        rank = max(URGENCIES.index(values["urgency"]), min(2, URGENCIES.index(existing["urgency"]) + int(raise_duplicate)))
        urgency = URGENCIES[rank]
        db.execute("""UPDATE shopping_items SET urgency = ?, category = ?, updated_by_member_id = ?, updated_at = ?,
            urgency_since = ? WHERE id = ?""", (urgency, values["category"] or existing["category"], actor, timestamp,
            timestamp if urgency != existing["urgency"] else existing["urgency_since"], existing["id"]))
        return existing["id"]
    return db.execute("""INSERT INTO shopping_items(list_id, family_id, name, normalized_name, urgency, category,
        created_by_member_id, updated_by_member_id, created_at, updated_at, urgency_since)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", (list_id, family_id(), values["name"], values["normalized_name"],
        values["urgency"], values["category"], actor, actor, timestamp, timestamp, timestamp)).lastrowid


def refresh():
    """Apply time rules lazily; no server queue is needed."""
    db = get_db()
    timestamp = utc_now().isoformat()
    for purchase in db.execute("""SELECT * FROM shopping_purchases WHERE family_id = ? AND return_at <= ?
        AND returned_at IS NULL AND return_cancelled_at IS NULL ORDER BY return_at, id""", (family_id(), timestamp)).fetchall():
        add(dict(purchase), purchase["bought_by_member_id"], purchase["return_at"], raise_duplicate=False)
        db.execute("UPDATE shopping_purchases SET returned_at = ? WHERE id = ?", (timestamp, purchase["id"]))
    cutoff = (utc_now() - timedelta(days=30)).isoformat()
    db.execute("UPDATE shopping_items SET urgency = 'week', urgency_since = ?, updated_at = ? WHERE family_id = ? AND urgency = 'background' AND urgency_since <= ?",
               (timestamp, timestamp, family_id(), cutoff))


def list_shopping(list_id=None):
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        list_id = resolve_list(list_id)
        refresh()
    items = [dict(row) for row in db.execute("SELECT * FROM shopping_items WHERE list_id = ? ORDER BY CASE urgency WHEN 'urgent' THEN 0 WHEN 'week' THEN 1 ELSE 2 END, category, id", (list_id,))]
    history = [dict(row) for row in db.execute("""SELECT p.*, m.name AS bought_by_name FROM shopping_purchases p
        JOIN members m ON m.id = p.bought_by_member_id WHERE p.list_id = ? ORDER BY p.bought_at DESC, p.id DESC LIMIT 200""", (list_id,))]
    lists = [dict(row) for row in db.execute("SELECT * FROM shopping_lists WHERE family_id = ? ORDER BY is_main DESC, id", (family_id(),))]
    return dict(items=items, purchases=history, lists=lists, list_id=list_id)


def save_item(payload, *, actor=None, raise_duplicate=True):
    values = validate(payload)
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        list_id = resolve_list(payload.get("list_id"))
        values["list_id"] = list_id
        refresh()
        existing = None if raise_duplicate else db.execute(
            "SELECT id FROM shopping_items WHERE list_id = ? AND normalized_name = ?",
            (list_id, values["normalized_name"])).fetchone()
        item_id = existing["id"] if existing else add(
            values, g.member.id if actor is None else actor, utc_now().isoformat(), raise_duplicate=raise_duplicate)
    return dict(get_db().execute("SELECT * FROM shopping_items WHERE id = ?", (item_id,)).fetchone())


def buy_item(item_id, payload):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    days = payload.get("return_in_days")
    if days is not None and (type(days) is not int or not 1 <= days <= 3650):
        raise DomainError("return days must be 1-3650")
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        refresh()
        item = db.execute("SELECT * FROM shopping_items WHERE id = ? AND family_id = ?", (item_id, family_id())).fetchone()
        if item is None:
            raise DomainError("shopping item not found")
        now = utc_now()
        return_at = (now + timedelta(days=days)).isoformat() if days else None
        db.execute("""INSERT INTO shopping_purchases(list_id, family_id, name, normalized_name, urgency, category,
            bought_by_member_id, bought_at, return_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (item["list_id"], family_id(), item["name"], item["normalized_name"], item["urgency"], item["category"], g.member.id, now.isoformat(), return_at))
        db.execute("DELETE FROM shopping_items WHERE id = ?", (item_id,))


def return_purchase(purchase_id, cancel=False):
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        purchase = db.execute("SELECT * FROM shopping_purchases WHERE id = ? AND family_id = ?", (purchase_id, family_id())).fetchone()
        if purchase is None:
            raise DomainError("purchase not found")
        if cancel:
            db.execute("UPDATE shopping_purchases SET return_cancelled_at = ? WHERE id = ?", (now_iso(), purchase_id))
        elif purchase["returned_at"] is None:
            add(dict(purchase), g.member.id, utc_now().isoformat(), raise_duplicate=False)
            db.execute("UPDATE shopping_purchases SET returned_at = ? WHERE id = ?", (utc_now().isoformat(), purchase_id))
