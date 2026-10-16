"""One-shot duty queries and untrusted voice completion drafts."""
from __future__ import annotations

from flask import g

from . import alice_oauth as oauth, duties
from .accounts import get_member
from .domain import DomainError, Member


def answer_duties(command, payload, respond, clean):
    from .alice_voice import aliases, local_today, normalize, query_date

    text = normalize(command)
    words = text.split()
    if not any(w.startswith(("дежур", "выполн", "сделал")) for w in words):
        return None
    if any(w.startswith(("назнач", "отмен", "удал", "продл", "оцен", "измени")) for w in words):
        return respond("Назначать и менять дежурства, подтверждать их и выставлять оценки можно только в приложении FamilyApp.", outcome="unsupported")
    write = any(w.startswith(("выполн", "сделал", "отмет")) for w in words)
    scope = oauth.DUTIES_WRITE if write else oauth.DUTIES_READ
    if not oauth.has_scope(scope):
        return respond("Для дежурств переподключите аккаунт FamilyApp и разрешите доступ к дежурствам.", outcome="permission_required")
    parent = get_member(g.alice_member_id)
    g.member = Member(id=parent["id"], name=parent["name"], role=parent["role"])
    today = local_today(payload.get("meta", {}))
    day = query_date(text, today, {})
    if day is None or day > today:
        return respond("Назовите дежурство за сегодня или прошедший день в новой команде.", outcome="needs_rephrase")
    data = duties.list_duties()
    rows = [r for r in data["occurrences"] if r["occurrence_date"] == day.isoformat() and not r["away"]]
    if not write:
        if not rows:
            return respond("На этот день дежурств нет.", outcome="handled")
        lines = [f"Дежурства на {day:%d.%m.%Y}."]
        for row in rows:
            status = {"confirmed": "выполнено", "pending": "ждёт подтверждения", "rejected": "на доработке"}.get(row["status"], "не выполнено")
            label = "Штрафное: " if row["kind"] == "penalty" else ""
            line = f"{label}{clean(row['title'])}: {clean(row['assigned_name'] or 'без назначения')}, {status}."
            if len(" ".join(lines)) + len(line) > 900:
                lines.append("Остальные дежурства — в приложении FamilyApp.")
                break
            lines.append(line)
        return respond(" ".join(lines), outcome="handled")
    members = [dict(row) for row in duties.get_db().execute("SELECT id, name FROM members WHERE family_id = ?", (duties.family_id(),))]
    matches = [m for m in members if any(f" {name} " in f" {text} " for name in aliases(m["name"]))]
    if len(matches) != 1:
        return respond("Повторите команду с именем исполнителя и названием дежурства, например: Миша выполнил дежурство помыть посуду.", outcome="needs_rephrase")
    # Match complete titles, never guess when two assignments have the same title.
    rows = [r for r in rows if f" {normalize(r['title'])} " in f" {text} "]
    if len(rows) != 1:
        return respond("Не удалось однозначно определить дежурство. Повторите команду с точным названием и датой или отметьте его в приложении.", outcome="needs_rephrase")
    row = rows[0]
    if row["status"] in ("pending", "confirmed"):
        return respond("Это дежурство уже отмечено. Проверить отметку можно в приложении.", outcome="already_submitted")
    try:
        duties.complete(row["id"], {"performer_member_id": matches[0]["id"]}, voice=True)
    except DomainError:
        return respond("Не удалось отправить отметку. Проверьте дежурство в приложении.", outcome="rejected")
    return respond("Отметка отправлена родителю на подтверждение: " + clean(row["title"]) + ".", outcome="handled")
