"""Scheduled duties, immutable daily assignments, confirmations and fairness."""
from __future__ import annotations

import json
import re
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import g

from .accounts import get_member
from .domain import DomainError, PermissionDenied, parse_date
from .persistence import family_id, get_db, now_iso


def utc_now():
    return datetime.now(timezone.utc)


def init_duties():
    get_db().executescript("""
        CREATE TABLE IF NOT EXISTS duties (
            id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL,
            created_by_member_id INTEGER NOT NULL, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS duty_revisions (
            id INTEGER PRIMARY KEY, duty_id INTEGER NOT NULL,
            effective_date TEXT NOT NULL, snapshot TEXT NOT NULL,
            actor_member_id INTEGER NOT NULL, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS duty_occurrences (
            id INTEGER PRIMARY KEY, duty_id INTEGER NOT NULL, occurrence_date TEXT NOT NULL,
            title TEXT NOT NULL, assigned_member_id INTEGER, reminder_time TEXT NOT NULL,
            timezone TEXT NOT NULL, revision INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'open', performer_member_id INTEGER,
            marked_by_member_id INTEGER, confirmed_by_member_id INTEGER,
            rating TEXT, marked_at TEXT, confirmed_at TEXT,
            UNIQUE(duty_id, occurrence_date)
        );
        CREATE TABLE IF NOT EXISTS duty_events (
            id INTEGER PRIMARY KEY, occurrence_id INTEGER NOT NULL,
            actor_member_id INTEGER NOT NULL, snapshot TEXT NOT NULL, created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS family_away_periods (
            id INTEGER PRIMARY KEY, family_id INTEGER NOT NULL,
            start_date TEXT NOT NULL, end_date TEXT NOT NULL,
            created_by_member_id INTEGER NOT NULL, created_at TEXT NOT NULL,
            cancelled_by_member_id INTEGER, cancelled_at TEXT
        );
        CREATE INDEX IF NOT EXISTS duties_family ON duties(family_id);
        CREATE INDEX IF NOT EXISTS duty_revisions_schedule ON duty_revisions(duty_id, effective_date);
    """)
    get_db().commit()


def get_duty(duty_id):
    row = get_db().execute("SELECT * FROM duties WHERE id = ? AND family_id = ?", (duty_id, family_id())).fetchone()
    if row is None:
        raise DomainError("duty not found")
    return dict(row)


def revisions(duty_id):
    return [dict(row, definition=json.loads(row["snapshot"])) for row in get_db().execute(
        "SELECT * FROM duty_revisions WHERE duty_id = ? ORDER BY effective_date, id", (duty_id,))]


def definition_on(duty_id, day):
    rows = revisions(duty_id)
    eligible = [row for row in rows if row["effective_date"] <= day.isoformat()]
    return eligible[-1] if eligible else None


def validate(payload):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    title = payload.get("title")
    if not isinstance(title, str) or not 1 <= len(title.strip()) <= 200:
        raise DomainError("duty title must be 1-200 characters")
    weekdays = payload.get("weekdays", list(range(1, 8)))
    if not isinstance(weekdays, list) or not weekdays or any(type(d) is not int or not 1 <= d <= 7 for d in weekdays):
        raise DomainError("select duty weekdays")
    assignments = payload.get("assignments", {})
    if not isinstance(assignments, dict):
        raise DomainError("invalid duty assignments")
    cleaned = {}
    for key, member in assignments.items():
        if key not in [str(d) for d in weekdays] or (member is not None and type(member) is not int):
            raise DomainError("invalid duty assignments")
        if member is not None:
            get_member(member)
        cleaned[key] = member
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
    start = parse_date(payload.get("start_date"), "start_date")
    return dict(title=title.strip(), weekdays=sorted(set(weekdays)), assignments=cleaned,
                reminder_time=clock, timezone=zone, active=active, start_date=start.isoformat())


def materialize(duty_id):
    """Freeze each due assignment before an edit can change the schedule."""
    db = get_db()
    rows = revisions(duty_id)
    for index, row in enumerate(rows):
        item = row["definition"]
        if not item["active"]:
            continue
        today = utc_now().astimezone(ZoneInfo(item["timezone"])).date()
        start = max(date.fromisoformat(row["effective_date"]), date.fromisoformat(item["start_date"]))
        end = min(today, date.fromisoformat(rows[index + 1]["effective_date"]) - timedelta(days=1)) if index + 1 < len(rows) else today
        latest = db.execute("SELECT MAX(occurrence_date) FROM duty_occurrences WHERE duty_id = ? AND revision = ?", (duty_id, row["id"])).fetchone()[0]
        if latest:
            start = max(start, date.fromisoformat(latest) + timedelta(days=1))
        day = start
        while day <= end:
            if day.isoweekday() in item["weekdays"]:
                db.execute("""INSERT OR IGNORE INTO duty_occurrences
                    (duty_id, occurrence_date, title, assigned_member_id, reminder_time, timezone, revision)
                    VALUES (?, ?, ?, ?, ?, ?, ?)""", (duty_id, day.isoformat(), item["title"],
                    item["assignments"].get(str(day.isoweekday())), item["reminder_time"], item["timezone"], row["id"]))
            day += timedelta(days=1)


def serialize_duty(duty_id):
    get_duty(duty_id)
    rows = revisions(duty_id)
    latest = rows[-1]
    return dict(id=duty_id, revision=latest["id"], effective_date=latest["effective_date"], **latest["definition"])


def save_duty(payload, duty_id=None):
    values = validate(payload)
    today = utc_now().astimezone(ZoneInfo(values["timezone"])).date()
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        if duty_id is None:
            if date.fromisoformat(values["start_date"]) < today:
                raise DomainError("new duty cannot start in the past")
            duty_id = db.execute("INSERT INTO duties(family_id, created_by_member_id, created_at) VALUES (?, ?, ?)",
                                 (family_id(), g.member.id, now_iso())).lastrowid
            effective = values["start_date"]
        else:
            get_duty(duty_id)
            materialize(duty_id)
            previous = revisions(duty_id)[-1]["definition"]
            # Keep a duty's timezone and initial start stable throughout its history.
            if values["timezone"] != previous["timezone"] or values["start_date"] != previous["start_date"]:
                raise DomainError("duty start and timezone cannot change")
            effective = max(today + timedelta(days=1), date.fromisoformat(previous["start_date"])).isoformat()
        db.execute("INSERT INTO duty_revisions(duty_id, effective_date, snapshot, actor_member_id, created_at) VALUES (?, ?, ?, ?, ?)",
                   (duty_id, effective, json.dumps(values), g.member.id, now_iso()))
        materialize(duty_id)
    return serialize_duty(duty_id)


def away_periods():
    return [dict(row) for row in get_db().execute(
        "SELECT * FROM family_away_periods WHERE family_id = ? AND cancelled_at IS NULL ORDER BY start_date DESC", (family_id(),))]


def is_away(day, periods=None):
    return any(p["start_date"] <= day <= p["end_date"] for p in (away_periods() if periods is None else periods))


def save_away(payload):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    start = parse_date(payload.get("start_date"), "start_date")
    end = parse_date(payload.get("end_date"), "end_date")
    if end < start:
        raise DomainError("away end precedes start")
    db = get_db()
    cursor = db.execute("INSERT INTO family_away_periods(family_id, start_date, end_date, created_by_member_id, created_at) VALUES (?, ?, ?, ?, ?)",
                        (family_id(), start.isoformat(), end.isoformat(), g.member.id, now_iso()))
    db.commit()
    return dict(id=cursor.lastrowid, start_date=start.isoformat(), end_date=end.isoformat())


def cancel_away(period_id):
    db = get_db()
    cursor = db.execute("UPDATE family_away_periods SET cancelled_at = ?, cancelled_by_member_id = ? WHERE id = ? AND family_id = ? AND cancelled_at IS NULL",
                        (now_iso(), g.member.id, period_id, family_id()))
    if not cursor.rowcount:
        raise DomainError("away period not found")
    db.commit()


def occurrence(occurrence_id):
    row = get_db().execute("""SELECT o.* FROM duty_occurrences o JOIN duties d ON d.id = o.duty_id
        WHERE o.id = ? AND d.family_id = ?""", (occurrence_id, family_id())).fetchone()
    if row is None:
        raise DomainError("duty occurrence not found")
    if not g.member.is_parent and row["assigned_member_id"] != g.member.id:
        raise PermissionDenied("duty access denied")
    return dict(row)


def complete(occurrence_id, payload):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        item = occurrence(occurrence_id)
        if item["status"] in ("confirmed", "pending"):
            raise DomainError("duty already submitted")
        if is_away(item["occurrence_date"]):
            raise DomainError("family is away on this day")
        performer = payload.get("performer_member_id", g.member.id)
        if type(performer) is not int:
            raise DomainError("performer is required")
        get_member(performer)
        if not g.member.is_parent and performer != g.member.id:
            raise PermissionDenied("children may only submit their own duty")
        rating = payload.get("rating", "normal") if g.member.is_parent else None
        if g.member.is_parent and rating not in ("bad", "normal", "great"):
            raise DomainError("invalid duty rating")
        db.execute("""UPDATE duty_occurrences SET status = ?, performer_member_id = ?, marked_by_member_id = ?,
            marked_at = ?, confirmed_by_member_id = ?, confirmed_at = ?, rating = ? WHERE id = ?""",
            ("confirmed" if g.member.is_parent else "pending", performer, g.member.id, now_iso(),
             g.member.id if g.member.is_parent else None, now_iso() if g.member.is_parent else None, rating, occurrence_id))
        record_event(occurrence_id)
    return occurrence(occurrence_id)


def review(occurrence_id, payload):
    if not isinstance(payload, dict):
        raise DomainError("request must be an object")
    approved = payload.get("approved")
    if type(approved) is not bool:
        raise DomainError("approval must be a boolean")
    rating = payload.get("rating", "normal") if approved else None
    if approved and rating not in ("bad", "normal", "great"):
        raise DomainError("invalid duty rating")
    db = get_db()
    with db:
        db.execute("BEGIN IMMEDIATE")
        item = occurrence(occurrence_id)
        if item["status"] != "pending":
            raise DomainError("duty is not awaiting confirmation")
        if is_away(item["occurrence_date"]):
            raise DomainError("family is away on this day")
        db.execute("UPDATE duty_occurrences SET status = ?, confirmed_by_member_id = ?, confirmed_at = ?, rating = ? WHERE id = ?",
                   ("confirmed" if approved else "rejected", g.member.id, now_iso(), rating, occurrence_id))
        record_event(occurrence_id)
    return occurrence(occurrence_id)


def record_event(occurrence_id):
    snapshot = occurrence(occurrence_id)
    snapshot["performer_name"] = get_member(snapshot["performer_member_id"])["name"]
    get_db().execute("INSERT INTO duty_events(occurrence_id, actor_member_id, snapshot, created_at) VALUES (?, ?, ?, ?)",
                     (occurrence_id, g.member.id, json.dumps(snapshot), now_iso()))


def list_duties():
    db = get_db()
    ids = [row[0] for row in db.execute("SELECT id FROM duties WHERE family_id = ? ORDER BY id DESC", (family_id(),))]
    with db:
        db.execute("BEGIN IMMEDIATE")
        for duty_id in ids:
            materialize(duty_id)
    periods = away_periods()
    definitions = [serialize_duty(duty_id) for duty_id in ids]
    rows = [dict(row) for row in db.execute("""SELECT o.* FROM duty_occurrences o JOIN duties d ON d.id = o.duty_id
        WHERE d.family_id = ? ORDER BY o.occurrence_date DESC, o.id DESC""", (family_id(),))]
    members = {row["id"]: row["name"] for row in db.execute("SELECT id, name FROM members WHERE family_id = ?", (family_id(),))}
    for row in rows:
        row["away"] = is_away(row["occurrence_date"], periods)
        row["assigned_name"] = members.get(row["assigned_member_id"])
        row["performer_name"] = members.get(row["performer_member_id"])
        row["marked_by_name"] = members.get(row["marked_by_member_id"])
        row["confirmed_by_name"] = members.get(row["confirmed_by_member_id"])
    statistics = {member: dict(member_id=member, name=name, missed=0, covered=0, completed=0,
                               pending=0, bad=0, normal=0, great=0, debt=0) for member, name in members.items()}
    for row in rows:
        if row["away"]:
            continue
        today = utc_now().astimezone(ZoneInfo(row["timezone"])).date().isoformat()
        assigned = statistics.get(row["assigned_member_id"])
        performer = statistics.get(row["performer_member_id"])
        if assigned and row["status"] == "pending":
            assigned["pending"] += 1
        if row["status"] == "confirmed" and performer:
            performer["completed"] += 1
            performer[row["rating"]] += 1
            if assigned and row["performer_member_id"] != row["assigned_member_id"]:
                performer["covered"] += 1
                assigned["missed"] += 1
        elif assigned and row["occurrence_date"] < today:
            assigned["missed"] += 1
    for stat in statistics.values():
        stat["debt"] = stat["missed"] - stat["covered"]
    suggestion = max(statistics.values(), key=lambda stat: (stat["debt"], -stat["member_id"]), default=None)
    if not g.member.is_parent:
        rows = [row for row in rows if row["assigned_member_id"] == g.member.id]
        definitions = [item for item in definitions if g.member.id in item["assignments"].values()]
        statistics = {g.member.id: statistics[g.member.id]}
        suggestion = None
    return dict(duties=definitions, occurrences=rows, statistics=list(statistics.values()), away_periods=periods,
                suggestion=suggestion if suggestion and suggestion["debt"] > 0 else None)


def reminders():
    now = utc_now()
    result = []
    periods = away_periods()
    for row in get_db().execute("SELECT id FROM duties WHERE family_id = ?", (family_id(),)):
        duty_id = row["id"]
        for offset in range(60):
            # Timezone is fixed for the duty, including scheduled edits.
            zone = revisions(duty_id)[-1]["definition"]["timezone"]
            day = now.astimezone(ZoneInfo(zone)).date() + timedelta(days=offset)
            revision = definition_on(duty_id, day)
            if not revision:
                continue
            item = revision["definition"]
            if not item["active"] or day.isoformat() < item["start_date"] or day.isoweekday() not in item["weekdays"]:
                continue
            if item["assignments"].get(str(day.isoweekday())) != g.member.id or is_away(day.isoformat(), periods):
                continue
            scheduled = datetime.fromisoformat(f"{day}T{item['reminder_time']}").replace(tzinfo=ZoneInfo(zone))
            done = get_db().execute("SELECT 1 FROM duty_occurrences WHERE duty_id = ? AND occurrence_date = ? AND status IN ('pending','confirmed')", (duty_id, day.isoformat())).fetchone()
            if scheduled > now and not done:
                result.append(dict(kind="duty", chore_id=duty_id, title=item["title"], occurrence_date=day.isoformat(),
                                   scheduled_at=scheduled.isoformat(), timezone=zone, revision=revision["id"],
                                   family_id=family_id(), member_id=g.member.id))
    return result
