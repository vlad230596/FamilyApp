"""Minimal shopping voice commands using the shared family shopping domain."""
from __future__ import annotations

import re

from flask import g

from . import alice_oauth as oauth
from . import shopping
from .domain import DomainError


def answer_shopping(command, previous, respond, clean):
    text = " ".join(command.strip().split()).strip(" .!?…")
    normalized = text.casefold().replace("ё", "е")
    add = re.fullmatch(r"(?:добавь|добавить|запиши|записать)(?:\s+пожалуйста)?\s+(?:в\s+)?(?:список покупок|список|покупки)(?:\s+(.+))?", normalized)
    trailing = re.fullmatch(r"(?:добавь|добавить|запиши|записать)\s+(.+?)\s+в\s+(?:список покупок|список|покупки)", normalized)
    read = normalized in {
        "что нужно купить", "что надо купить", "что купить", "нужно купить", "список покупок",
        "что в списке покупок", "что у нас в списке покупок", "прочитай список покупок",
        "озвучь список покупок", "покажи список покупок", "какие у нас покупки",
    }
    pending = previous.get("pending") == "shopping_add"
    if pending and normalized in {"отмена", "не надо", "нет", "отмени добавление"}:
        return respond("Добавление отменено.", end=True)
    if not (add or trailing or read) and re.search(r"\b(?:купил[аи]?|куплено|удали|убери|вычеркни)\b", normalized):
        return respond("Отмечать покупки и удалять товары пока можно только в приложении.", end=True)
    if not (add or trailing or read or pending):
        return None
    permission = oauth.SHOPPING_READ if read else oauth.SHOPPING_WRITE
    if not oauth.has_scope(permission):
        return respond("Для списка покупок переподключите аккаунт FamilyApp и разрешите доступ к покупкам.", end=True)
    if read:
        items = shopping.list_shopping()["items"]
        if not items:
            return respond("Список покупок пуст.", end=True)
        lines = ["Нужно купить:"]
        for index, item in enumerate(items):
            label = clean(item["name"])
            if sum(map(len, lines)) + len(label) + 80 > 1700:
                lines.append(f"Остальные товары — в приложении. Всего в списке {len(items)}.")
                break
            lines.append(label + ("." if index == len(items) - 1 else ";"))
        return respond(" ".join(lines), end=True)
    match = add or trailing
    if match and match.group(1):
        # Preserve the original spelling and punctuation of the item name.
        start, end = match.span(1)
        name = text[start:end]
    elif pending and not match:
        name = text
    else:
        return respond("Что добавить в список покупок? Назовите один товар.", context={"pending": "shopping_add"})
    if len(name) > 200 or not re.search(r"[\w]", name):
        return respond("Назовите один товар длиной до двухсот символов.", context={"pending": "shopping_add"})
    try:
        item = shopping.save_item({"name": name}, actor=g.alice_member_id, raise_duplicate=False)
    except DomainError:
        return respond("Не удалось добавить товар. Проверьте название.", end=True)
    return respond("В списке покупок: " + clean(item["name"]) + ".", end=True)
