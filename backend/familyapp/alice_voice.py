"""Read-only restriction queries and deterministic Russian voice phrasing."""
from __future__ import annotations

import re
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from flask import current_app, g
from itsdangerous import BadSignature, URLSafeTimedSerializer

from .persistence import list_children, list_restrictions

HELP = "Можно спросить: какие сегодня ограничения у ребят, что нельзя Мише или когда ему снова можно мультики."
NAME_GROUPS = (
    ("михаил", "миша", "мишенька"), ("мария", "маша", "машенька"),
    ("александр", "саша", "саня"), ("александра", "саша"),
    ("анна", "аня", "анюта"), ("елизавета", "лиза"),
    ("дмитрий", "дима"), ("екатерина", "катя"), ("сергей", "сережа"),
    ("алексей", "леша"), ("петр", "петя"), ("иван", "ваня"),
    ("евгений", "женя"), ("евгения", "женя"), ("николай", "коля"),
    ("наталья", "наташа"), ("владимир", "вова"), ("дарья", "даша"),
    ("софия", "софья", "соня"), ("виктория", "вика"),
)
TOPICS = {
    "cartoons": ("мультик", "мультфильм", "мульт", "cartoon"),
    "phone": ("телефон", "смартфон", "phone"),
    "tablet": ("планшет", "tablet"),
    "games": ("игр", "игра", "games"),
    "tv": ("телевизор", "телевидени", "tv"),
    "computer": ("компьютер", "ноутбук", "computer"),
}


def normalize(value):
    return " ".join(re.findall(r"[а-яa-z0-9]+", value.lower().replace("ё", "е")))


def forms(name):
    name = normalize(name)
    values = {name}
    if name.endswith("ия"):
        values.update(name[:-1] + suffix for suffix in ("и", "ю", "ей"))
    elif name.endswith("а"):
        values.update(name[:-1] + suffix for suffix in ("ы", "и", "е", "у", "ой"))
    elif name.endswith("я"):
        values.update(name[:-1] + suffix for suffix in ("и", "е", "ю", "ей"))
    elif name.endswith(("й", "ь")):
        values.update(name[:-1] + suffix for suffix in ("я", "ю", "ем", "е"))
    else:
        values.update(name + suffix for suffix in ("а", "у", "ом", "е"))
    return values


def aliases(name):
    normalized = normalize(name)
    names = {normalized}
    for group in NAME_GROUPS:
        if normalized in group:
            names.update(group)
    return set().union(*(forms(n) for n in names))


def topics(text):
    words = normalize(text).split()
    return {key for key, prefixes in TOPICS.items() if any(
        word.startswith(prefix) for word in words for prefix in prefixes)}


def clean_label(text):
    # Use response.text rather than user-controlled TTS markup.
    return re.sub(r"[\x00-\x1f<>\[\]{}]", "", text or "ограничение")[:80].strip()


def spoken_response(text, end=False, context=None):
    result = {"version": "1.0", "response": {"text": text, "end_session": end}}
    if context is not None:
        context = {**context, "grant_id": g.alice_grant_id}
        result["session_state"] = {"context": state_serializer().dumps(context)}
    return result


def state_serializer():
    return URLSafeTimedSerializer(current_app.config["ALICE_COOKIE_SECRET"], salt="alice-voice-context")


def previous_context(payload):
    try:
        state = payload.get("state", {}).get("session", {}).get("context", "")
        context = state_serializer().loads(state, max_age=1800)
        if context.get("grant_id") == g.alice_grant_id:
            return context
    except (BadSignature, AttributeError, TypeError):
        pass
    return {}


def local_today(meta):
    try:
        zone = ZoneInfo(meta.get("timezone", current_app.config["ALICE_TIMEZONE"]))
    except (ZoneInfoNotFoundError, TypeError, ValueError):
        zone = ZoneInfo(current_app.config["ALICE_TIMEZONE"])
    return datetime.now(timezone.utc).astimezone(zone).date()


def query_date(text, today, previous):
    words = set(text.split())
    relative = {"сегодня": 0, "завтра": 1, "послезавтра": 2, "вчера": -1}
    found = [today + timedelta(days=offset) for word, offset in relative.items() if word in words]
    for explicit in re.finditer(r"\b(\d{4}) (\d{2}) (\d{2})\b", text):
        try:
            found.append(date(*map(int, explicit.groups())))
        except ValueError:
            return None
    if len(set(found)) > 1:
        return None
    if found:
        return found[0]
    if any(w.startswith(("понедельник", "вторник", "сред", "четверг", "пятниц", "суббот", "воскресень", "недел", "вечер", "утр", "ноч", "месяц", "январ", "феврал", "март", "апрел", "мая", "июн", "июл", "август", "сентябр", "октябр", "ноябр", "декабр")) for w in words) or "через" in words or any(w.isdigit() for w in words):
        return None
    return date.fromisoformat(previous["date"]) if previous.get("date") else today


def active_on(restrictions, day):
    # stored_status avoids interpreting historical dates using the server's current day.
    return [r for r in restrictions if r["stored_status"] == "active"
            and r["start_date"] <= day.isoformat() <= r["end_date"]]


def type_matches(restriction, topic):
    if topic in TOPICS:
        return topic in topics(restriction["type_name"] or "")
    return normalize(restriction["type_name"] or "") == topic


def next_free_day(restrictions, day):
    end = max(date.fromisoformat(r["end_date"]) for r in active_on(restrictions, day))
    # Merge adjacent and overlapping intervals, including already scheduled ones.
    for row in sorted(restrictions, key=lambda r: r["start_date"]):
        if row["stored_status"] == "active" and date.fromisoformat(row["start_date"]) <= (end + timedelta(days=1) if end < date.max else end):
            end = max(end, date.fromisoformat(row["end_date"]))
    return end + timedelta(days=1) if end < date.max else None


def answer(payload):
    utterance = payload.get("request", {})
    if not isinstance(utterance, dict) or not isinstance(utterance.get("command", ""), str):
        return spoken_response("Не удалось разобрать вопрос. " + HELP)
    text = normalize(utterance.get("command", "")[:2048])
    previous = previous_context(payload)
    if "account_linking_complete_event" in payload:
        text = "какие сегодня ограничения у ребят"
    if text in {"хватит", "стоп", "выход", "закрой навык", "до свидания"}:
        return spoken_response("До встречи!", end=True)
    if not text or text in {"помощь", "что ты умеешь", "что ты можешь"}:
        return spoken_response("Это семейный помощник. " + HELP)
    words = set(text.split())
    if any(word.startswith(("отмен", "сним", "продл", "добав", "разреш", "запрет", "измени", "убери")) for word in words):
        return spoken_response("Изменять ограничения можно только в приложении FamilyApp. Я могу рассказать, какие ограничения действуют.")
    recognized = any(w.startswith(("огранич", "нельзя", "можно", "может", "мультик", "мультфильм")) for w in words)
    followup = bool(previous) and (previous.get("pending") or text.startswith("а ") or text in {"повтори", "повторить", "еще раз"})
    if not recognized and not followup:
        return spoken_response("Я пока отвечаю на вопросы об ограничениях. " + HELP)
    children = list_children()
    tokens = set(text.split())
    matches = [child for child in children if any(f" {variant} " in f" {text} " for variant in aliases(child["name"]))]
    if len(matches) > 1:
        return spoken_response("Уточните одного ребёнка: " + ", ".join(clean_label(c["name"]) for c in matches) + ".")
    all_children = bool(words & {"ребят", "ребята", "детей", "дети", "всех"})
    child_id = matches[0]["id"] if matches else (None if all_children else previous.get("child_id") if followup else None)
    day = query_date(text, local_today(payload.get("meta", {})), previous if followup else {})
    if day is None:
        return spoken_response("Уточните один день: сегодня, завтра или послезавтра.")
    # Explicit unknown names must never fall back to all children or the previous child.
    named = re.search(r"\b(?:у|для) ([а-яa-z]+)\b", text)
    permission_name = re.search(r"\bможно ([а-яa-z]+)\b", text)
    forbidden_name = re.search(r"\bнельзя ([а-яa-z]+)\b", text)
    restriction_name = re.search(r"\bограничени[а-я]* ([а-яa-z]+)\b", text)
    neutral = {"ребят", "ребенка", "детей", "всех", "него", "нее", "них", "меня", "сегодня", "завтра", "послезавтра", "смотреть", "посмотреть", "мультики", "мультфильмы", "ему", "ей", "им", "будет", "снова", "уже", "играть", "пользоваться", "делать", "телефон", "планшет", "у", "на", "для", "есть", "действуют", "сейчас", "были", "будут", "вчера"}
    known_name_words = set().union(*(forms(name) for group in NAME_GROUPS for name in group))
    if not matches and (any(m and m[1] not in neutral for m in (named, permission_name, forbidden_name, restriction_name)) or tokens & known_name_words):
        return spoken_response("Не нашла такого ребёнка в подключённой семье. Назовите имя, указанное в FamilyApp.")
    found_topics = topics(text)
    if len(found_topics) > 1:
        return spoken_response("Уточните одно занятие, например мультики или телефон.")
    topic = next(iter(found_topics), None)
    restrictions = list_restrictions()
    custom_names = {normalize(r["type_name"] or "") for r in restrictions}
    custom_matches = [name for name in custom_names if name and f" {name} " in f" {text} "]
    if topic is None and custom_matches:
        if len(custom_matches) > 1:
            return spoken_response("Уточните один тип ограничения.")
        topic = custom_matches[0]
    if topic is None and followup:
        topic = previous.get("topic")
    mode = "until" if words & {"когда", "докуда"} or "до какого" in text else "permission" if words & {"можно", "может"} else "summary"
    if followup and mode == "summary" and not any(w.startswith("огранич") for w in words):
        mode = previous.get("mode", "summary")
    if all_children and not words & {"можно", "может", "когда"}:
        mode, topic = "summary", None
    context = {"child_id": child_id, "topic": topic, "date": day.isoformat(), "mode": mode}
    if mode in {"permission", "until"}:
        if child_id is None:
            return spoken_response("Про какого ребёнка вы спрашиваете? Назовите его имя.", context={**context, "pending": True})
        if topic is None:
            return spoken_response("Какое занятие проверить? Например: можно Мише сегодня мультики?", context={**context, "pending": True})
    selected = [r for r in restrictions if (child_id is None or r["child_id"] == child_id)
                and (topic is None or type_matches(r, topic))]
    current = active_on(selected, day)
    if mode in {"permission", "until"}:
        child = next((c for c in children if c["id"] == child_id), None)
        if child is None:
            return spoken_response("Назовите имя ребёнка из подключённой семьи.")
        prefix = clean_label(child["name"]) + ": "
        if not current:
            return spoken_response(prefix + f"в FamilyApp на {day:%d.%m.%Y} нет ограничения на это занятие.", context=context)
        free = next_free_day(selected, day)
        label = clean_label(current[0]["type_name"])
        ending = f"По текущему расписанию оно перестанет действовать с {free:%d.%m.%Y}." if free else "Дата окончания выходит за пределы календаря. Проверьте её в приложении."
        return spoken_response(prefix + f"на {day:%d.%m.%Y} действует ограничение «{label}». " + ending, context=context)
    if not current:
        who = clean_label(matches[0]["name"]) + ": " if matches else ""
        return spoken_response(who + f"на {day:%d.%m.%Y} ограничений в FamilyApp нет.", context=context)
    lines = [f"Ограничения на {day:%d.%m.%Y}."]
    for child in children:
        rows = [r for r in current if r["child_id"] == child["id"]]
        if not rows:
            continue
        for row in rows:
            line = f"{clean_label(child['name'])}: {clean_label(row['type_name'])}, последний день — {date.fromisoformat(row['end_date']):%d.%m.%Y}."
            if sum(len(s) for s in lines) + len(line) > 1700:
                lines.append("Остальные ограничения можно посмотреть в приложении FamilyApp.")
                return spoken_response(" ".join(lines), context=context)
            lines.append(line)
    return spoken_response(" ".join(lines), context=context)
