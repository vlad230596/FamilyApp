"""Shared shopping list, urgency, purchases and scheduled returns."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from uuid import uuid4

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
    # Integer SQLite IDs can be reused after deletion. Offline actions need an
    # immutable identity for each occurrence of a shopping item.
    if 'item_key' not in [row['name'] for row in db.execute('PRAGMA table_info(shopping_items)')]:
        db.execute('ALTER TABLE shopping_items ADD COLUMN item_key TEXT')
    for row in db.execute('SELECT id FROM shopping_items WHERE item_key IS NULL').fetchall():
        db.execute('UPDATE shopping_items SET item_key = ? WHERE id = ?', (uuid4().hex, row['id']))
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS shopping_item_key ON shopping_items(item_key)')
    if 'source_item_key' not in [row['name'] for row in db.execute('PRAGMA table_info(shopping_purchases)')]:
        db.execute('ALTER TABLE shopping_purchases ADD COLUMN source_item_key TEXT')
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS shopping_purchase_source ON shopping_purchases(source_item_key)')
    db.execute('''CREATE TABLE IF NOT EXISTS shopping_operations (
        family_id INTEGER NOT NULL, member_id INTEGER NOT NULL, operation_id TEXT NOT NULL,
        payload TEXT NOT NULL, result TEXT NOT NULL, created_at TEXT NOT NULL,
        PRIMARY KEY (family_id, member_id, operation_id))''')
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
        created_by_member_id, updated_by_member_id, created_at, updated_at, urgency_since, item_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", (list_id, family_id(), values["name"], values["normalized_name"],
        values["urgency"], values["category"], actor, actor, timestamp, timestamp, timestamp, uuid4().hex)).lastrowid


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
        return _read_list(list_id)


def _read_list(list_id):
    db = get_db()
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
        _record_purchase(item, days, utc_now())


def _record_purchase(item, days, bought_at):
    db = get_db()
    return_at = (bought_at + timedelta(days=days)).isoformat() if days else None
    purchase_id = db.execute('''INSERT INTO shopping_purchases(list_id, family_id, name, normalized_name,
        urgency, category, bought_by_member_id, bought_at, return_at, source_item_key)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        (item['list_id'], family_id(), item['name'], item['normalized_name'], item['urgency'],
         item['category'], g.member.id, bought_at.isoformat(), return_at, item['item_key'])).lastrowid
    db.execute('DELETE FROM shopping_items WHERE id = ?', (item['id'],))
    return purchase_id


def snapshot():
    """Fetch every list so opening another list offline does not need a request."""
    db = get_db()
    with db:
        db.execute('BEGIN IMMEDIATE')
        resolve_list()
        refresh()
        lists = [dict(row) for row in db.execute(
            'SELECT * FROM shopping_lists WHERE family_id = ? ORDER BY is_main DESC, id', (family_id(),))]
        return {'lists': lists, 'snapshots': [_read_list(row['id']) for row in lists]}


def _operation_result(operation_id):
    if not isinstance(operation_id, str) or not 16 <= len(operation_id) <= 80:
        raise DomainError('invalid shopping operation id')
    row = get_db().execute('''SELECT result FROM shopping_operations
        WHERE family_id = ? AND member_id = ? AND operation_id = ?''',
        (family_id(), g.member.id, operation_id)).fetchone()
    return json.loads(row['result']) if row else None


def _purchase_result(purchase, status, **extra):
    bought_at = datetime.fromisoformat(purchase['bought_at'])
    days = ((datetime.fromisoformat(purchase['return_at']) - bought_at).days
            if purchase['return_at'] else None)
    return dict(status=status, purchase_id=purchase['id'], item_key=purchase['source_item_key'],
                name=purchase['name'], return_in_days=days, return_at=purchase['return_at'],
                can_change=purchase['returned_at'] is None and purchase['return_cancelled_at'] is None, **extra)


def sync_operation(payload):
    """Apply one durable client command and its receipt in the same transaction."""
    if not isinstance(payload, dict):
        raise DomainError('request must be an object')
    operation_id = payload.get('operation_id')
    if not isinstance(operation_id, str) or not 16 <= len(operation_id) <= 80:
        raise DomainError('invalid shopping operation id')
    if type(payload.get('family_id')) is not int or payload['family_id'] != family_id():
        raise DomainError('shopping operation family mismatch')
    encoded = json.dumps(payload, sort_keys=True, ensure_ascii=False)
    db = get_db()
    with db:
        db.execute('BEGIN IMMEDIATE')
        previous = db.execute('''SELECT payload, result FROM shopping_operations
            WHERE family_id = ? AND member_id = ? AND operation_id = ?''',
            (family_id(), g.member.id, operation_id)).fetchone()
        if previous:
            if previous['payload'] != encoded:
                raise DomainError('shopping operation id reused')
            return json.loads(previous['result'])
        refresh()
        kind = payload.get('kind')
        if kind == 'add':
            values = validate(payload)
            values['list_id'] = resolve_list(payload.get('list_id'))
            # Offline duplicates merge without escalating urgency on every retry.
            existing = db.execute('SELECT * FROM shopping_items WHERE list_id = ? AND normalized_name = ?',
                                  (values['list_id'], values['normalized_name'])).fetchone()
            if existing and existing['category']:
                values['category'] = existing['category']
            item_id = add(values, g.member.id, now_iso(), raise_duplicate=False)
            item = db.execute('SELECT * FROM shopping_items WHERE id = ?', (item_id,)).fetchone()
            result = dict(status='applied', item_key=item['item_key'], item_id=item_id)
        elif kind == 'buy':
            days = payload.get('return_in_days')
            if days is not None and (type(days) is not int or not 1 <= days <= 3650):
                raise DomainError('return days must be 1-3650')
            item_key = payload.get('item_key')
            if payload.get('add_operation_id'):
                addition = _operation_result(payload['add_operation_id'])
                if addition is None or addition.get('item_key') is None:
                    raise DomainError('shopping addition not synchronized')
                item_key = addition['item_key']
            if not isinstance(item_key, str) or len(item_key) != 32:
                raise DomainError('invalid shopping item key')
            item = db.execute('SELECT * FROM shopping_items WHERE item_key = ? AND family_id = ?',
                              (item_key, family_id())).fetchone()
            purchase = db.execute('SELECT * FROM shopping_purchases WHERE source_item_key = ? AND family_id = ?',
                                  (item_key, family_id())).fetchone()
            if purchase:
                result = _purchase_result(purchase, 'already_bought')
                if result['return_in_days'] != days:
                    result['status'] = 'conflict'
                    result['requested_days'] = days
            elif item:
                try:
                    bought_at = datetime.fromisoformat(payload['occurred_at'])
                    if bought_at.tzinfo is None:
                        raise ValueError()
                    bought_at = bought_at.astimezone(timezone.utc)
                    if not datetime(2000, 1, 1, tzinfo=timezone.utc) <= bought_at <= utc_now() + timedelta(minutes=5):
                        raise ValueError()
                except (ValueError, TypeError, KeyError):
                    raise DomainError('invalid shopping purchase time') from None
                purchase_id = _record_purchase(item, days, bought_at)
                purchase = db.execute('SELECT * FROM shopping_purchases WHERE id = ?', (purchase_id,)).fetchone()
                result = _purchase_result(purchase, 'applied')
            else:
                raise DomainError('shopping item not found')
        elif kind == 'resolve':
            conflict = _operation_result(payload.get('conflict_operation_id'))
            if not conflict or conflict['status'] != 'conflict':
                raise DomainError('shopping conflict not found')
            purchase = db.execute('SELECT * FROM shopping_purchases WHERE id = ? AND family_id = ?',
                                  (conflict['purchase_id'], family_id())).fetchone()
            if purchase is None or payload.get('choice') not in ('server', 'local'):
                raise DomainError('invalid shopping conflict choice')
            result = _purchase_result(purchase, 'applied')
            if payload['choice'] == 'local':
                if not result['can_change'] or purchase['return_at'] != conflict['return_at']:
                    result.update(status='conflict', requested_days=conflict['requested_days'])
                else:
                    days = conflict['requested_days']
                    return_at = ((datetime.fromisoformat(purchase['bought_at']) + timedelta(days=days)).isoformat()
                                 if days else None)
                    db.execute('UPDATE shopping_purchases SET return_at = ? WHERE id = ?', (return_at, purchase['id']))
                    purchase = db.execute('SELECT * FROM shopping_purchases WHERE id = ?', (purchase['id'],)).fetchone()
                    result = _purchase_result(purchase, 'applied')
        else:
            raise DomainError('invalid shopping operation kind')
        db.execute('''INSERT INTO shopping_operations VALUES (?, ?, ?, ?, ?, ?)''',
                   (family_id(), g.member.id, operation_id, encoded, json.dumps(result), now_iso()))
    return result


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
