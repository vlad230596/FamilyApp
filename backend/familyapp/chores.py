"""Recurring checks, their schedules and immutable answers."""
from __future__ import annotations

import json
import re
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import g

from .accounts import get_member
from .domain import DomainError, PermissionDenied, parse_date
from .persistence import family_id, get_db, now_iso


def init_chores() -> None:
    get_db().executescript("""
        CREATE TABLE IF NOT EXISTS chores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            family_id INTEGER NOT NULL REFERENCES families(id),
            title TEXT NOT NULL,
            responsible_member_id INTEGER NOT NULL REFERENCES members(id),
            start_date TEXT NOT NULL,
            interval_days INTEGER NOT NULL,
            weekdays TEXT NOT NULL,
            reminder_time TEXT NOT NULL,
            timezone TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            revision INTEGER NOT NULL DEFAULT 1,
            created_by_member_id INTEGER NOT NULL REFERENCES members(id),
            updated_by_member_id INTEGER NOT NULL REFERENCES members(id),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chore_answers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chore_id INTEGER NOT NULL REFERENCES chores(id),
            occurrence_date TEXT NOT NULL,
            answer INTEGER NOT NULL,
            actor_member_id INTEGER NOT NULL REFERENCES members(id),
            title TEXT NOT NULL,
            revision INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(chore_id, occurrence_date)
        );
        CREATE TABLE IF NOT EXISTS chore_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chore_id INTEGER NOT NULL REFERENCES chores(id),
            actor_member_id INTEGER NOT NULL REFERENCES members(id),
            snapshot TEXT NOT NULL,
            created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS chores_family ON chores(family_id);
    """)
    get_db().commit()


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def validate_schedule(payload: dict) -> dict:
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    title = payload.get("title")
    if not isinstance(title, str) or not 1 <= len(title.strip()) <= 200:
        raise DomainError("chore title must be 1-200 characters")
    member_id = payload.get("responsible_member_id")
    if type(member_id) is not int:
        raise DomainError("responsible member is required")
    if not get_member(member_id)["has_account"]:
        raise DomainError("responsible member needs an account")
    start = parse_date(payload.get("start_date"), "start_date")
    interval = payload.get("interval_days", 1)
    if type(interval) is not int or not 1 <= interval <= 365:
        raise DomainError("interval_days must be 1-365")
    weekdays = payload.get("weekdays", [])
    if not isinstance(weekdays, list) or any(type(d) is not int or not 1 <= d <= 7 for d in weekdays):
        raise DomainError("weekdays must contain numbers 1-7")
    if weekdays and interval != 1:
        raise DomainError("choose either interval or weekdays")
    clock = payload.get("reminder_time")
    if not isinstance(clock, str) or not re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", clock):
        raise DomainError("reminder_time must be HH:MM")
    zone = payload.get("timezone")
    try:
        if not isinstance(zone, str):
            raise ValueError()
        ZoneInfo(zone)
    except (ValueError, ZoneInfoNotFoundError):
        raise DomainError("timezone must be an IANA name") from None
    active = payload.get("active", True)
    if type(active) is not bool:
        raise DomainError("active must be a boolean")
    return dict(title=title.strip(), responsible_member_id=member_id,
                start_date=start.isoformat(), interval_days=interval,
                weekdays=json.dumps(sorted(set(weekdays))), reminder_time=clock,
                timezone=zone, active=int(active))


def scheduled_on(chore: dict, day: date) -> bool:
    start = date.fromisoformat(chore["start_date"])
    if day < start:
        return False
    weekdays = chore["weekdays"]
    if isinstance(weekdays, str):
        weekdays = json.loads(weekdays)
    return day.isoweekday() in weekdays if weekdays else (day - start).days % chore["interval_days"] == 0


def scheduled_at(chore: dict, day: date) -> datetime:
    return datetime.combine(day, time.fromisoformat(chore["reminder_time"]), ZoneInfo(chore["timezone"]))


def get_chore(chore_id: int) -> dict:
    row = get_db().execute("SELECT * FROM chores WHERE id = ? AND family_id = ?",
                           (chore_id, family_id())).fetchone()
    if row is None:
        raise DomainError("chore not found")
    chore = dict(row)
    if not g.member.is_parent and chore["responsible_member_id"] != g.member.id:
        raise PermissionDenied("chore access denied")
    return chore


def serialize(chore: dict) -> dict:
    result = dict(chore)
    result["weekdays"] = json.loads(chore["weekdays"])
    result["active"] = bool(chore["active"])
    result["responsible_name"] = get_member(chore["responsible_member_id"])["name"]
    now = utc_now()
    today = now.astimezone(ZoneInfo(chore["timezone"])).date()
    # A late answer belongs to the latest due check, never to a future check.
    due = today if scheduled_at(chore, today) <= now else today - timedelta(days=1)
    for _ in range(366):
        if scheduled_on(chore, due):
            break
        due -= timedelta(days=1)
    else:
        due = None
    result["due_date"] = due.isoformat() if due is not None and chore["active"] else None
    result["due_answer"] = None
    if result["due_date"]:
        answer = get_db().execute("SELECT answer FROM chore_answers WHERE chore_id = ? AND occurrence_date = ?",
                                  (chore["id"], result["due_date"])).fetchone()
        if answer is not None:
            result["due_answer"] = bool(answer["answer"])
    next_day = max(today, date.fromisoformat(chore["start_date"]))
    result["next_at"] = None
    if chore["active"]:
        for _ in range(366):
            if scheduled_on(chore, next_day) and scheduled_at(chore, next_day) > now:
                result["next_at"] = scheduled_at(chore, next_day).isoformat()
                break
            next_day += timedelta(days=1)
    return result


def list_chores() -> list[dict]:
    rows = get_db().execute("SELECT * FROM chores WHERE family_id = ? ORDER BY active DESC, id DESC",
                            (family_id(),)).fetchall()
    return [serialize(dict(row)) for row in rows
            if g.member.is_parent or row["responsible_member_id"] == g.member.id]


def save_chore(payload: dict, chore_id: int | None = None) -> dict:
    values = validate_schedule(payload)
    db = get_db()
    timestamp = now_iso()
    if chore_id is None:
        values.update(family_id=family_id(), created_by_member_id=g.member.id,
                      updated_by_member_id=g.member.id, created_at=timestamp, updated_at=timestamp)
        columns = list(values)
        cursor = db.execute(f"INSERT INTO chores ({', '.join(columns)}) VALUES ({', '.join('?' for _ in columns)})",
                            tuple(values.values()))
        chore_id = cursor.lastrowid
    else:
        get_chore(chore_id)
        values.update(updated_by_member_id=g.member.id, updated_at=timestamp)
        db.execute(f"UPDATE chores SET {', '.join(f'{key} = ?' for key in values)}, revision = revision + 1 WHERE id = ?",
                   (*values.values(), chore_id))
    chore = get_chore(chore_id)
    db.execute("INSERT INTO chore_events (chore_id, actor_member_id, snapshot, created_at) VALUES (?, ?, ?, ?)",
               (chore_id, g.member.id, json.dumps(chore), timestamp))
    db.commit()
    return serialize(chore)


def answer_chore(chore_id: int, payload: dict) -> dict:
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    if type(payload.get("answer")) is not bool:
        raise DomainError("answer must be a boolean")
    day = parse_date(payload.get("occurrence_date"), "occurrence_date")
    db = get_db()
    db.execute("BEGIN IMMEDIATE")
    try:
        chore = get_chore(chore_id)
        if chore["responsible_member_id"] != g.member.id:
            raise PermissionDenied("only responsible member may answer")
        if type(payload.get("revision")) is not int or payload["revision"] != chore["revision"]:
            raise DomainError("chore changed; refresh before answering")
        if not chore["active"] or not scheduled_on(chore, day) or scheduled_at(chore, day) > utc_now():
            raise DomainError("check is not due")
        existing = db.execute("SELECT * FROM chore_answers WHERE chore_id = ? AND occurrence_date = ?",
                              (chore_id, day.isoformat())).fetchone()
        if existing:
            if bool(existing["answer"]) != payload["answer"] or existing["actor_member_id"] != g.member.id:
                raise DomainError("check already answered")
        else:
            db.execute("""INSERT INTO chore_answers
                (chore_id, occurrence_date, answer, actor_member_id, title, revision, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (chore_id, day.isoformat(), int(payload["answer"]), g.member.id, chore["title"], chore["revision"], now_iso()))
        db.commit()
    except Exception:
        db.rollback()
        raise
    return serialize(chore)


def answer_history(chore_id: int) -> list[dict]:
    get_chore(chore_id)
    rows = get_db().execute("""SELECT a.*, m.name AS actor_name FROM chore_answers a
        JOIN members m ON m.id = a.actor_member_id WHERE a.chore_id = ?
        ORDER BY a.occurrence_date DESC LIMIT 100""", (chore_id,)).fetchall()
    return [dict(row, answer=bool(row["answer"])) for row in rows]


def reminders() -> list[dict]:
    """A bounded local schedule, refreshed whenever the client syncs."""
    now = utc_now()
    result = []
    for chore in list_chores():
        if not chore["active"] or chore["responsible_member_id"] != g.member.id:
            continue
        today = now.astimezone(ZoneInfo(chore["timezone"])).date()
        for offset in range(60):
            day = today + timedelta(days=offset)
            if not scheduled_on(chore, day) or scheduled_at(chore, day) <= now:
                continue
            answered = get_db().execute("SELECT 1 FROM chore_answers WHERE chore_id = ? AND occurrence_date = ?",
                                        (chore["id"], day.isoformat())).fetchone()
            if not answered:
                result.append(dict(chore_id=chore["id"], title=chore["title"],
                    occurrence_date=day.isoformat(), scheduled_at=scheduled_at(chore, day).isoformat(),
                    timezone=chore["timezone"], revision=chore["revision"],
                    family_id=family_id(), member_id=g.member.id))
    # Stay below common Android alarm limits even for large families.
    return sorted(result, key=lambda item: datetime.fromisoformat(item["scheduled_at"]))[:200]
