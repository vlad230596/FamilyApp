"""Conservative, offline normalization of single-word voice shopping names."""
from __future__ import annotations

from functools import lru_cache
import re

from pymorphy3 import MorphAnalyzer


# Keys are dictionary lemmas; values are natural shopping-list labels. Keep
# plural labels where singular lemmas would be awkward (e.g. vegetables).
# This allowlist intentionally excludes arbitrary nouns, brands and phrases.
PRODUCT_NAMES = {
    "овощ": "овощи", "фрукт": "фрукты", "ягода": "ягоды",
    "помидор": "помидоры", "томат": "томаты", "огурец": "огурцы",
    "картофель": "картофель", "картошка": "картошка", "морковь": "морковь",
    "капуста": "капуста", "свекла": "свёкла", "лук": "лук",
    "чеснок": "чеснок", "кабачок": "кабачки", "баклажан": "баклажаны",
    "перец": "перец", "зелень": "зелень", "укроп": "укроп",
    "петрушка": "петрушка", "салат": "салат", "гриб": "грибы",
    "яблоко": "яблоки", "груша": "груши", "банан": "бананы",
    "апельсин": "апельсины", "мандарин": "мандарины", "лимон": "лимоны",
    "виноград": "виноград", "клубника": "клубника", "малина": "малина",
    "молоко": "молоко", "кефир": "кефир", "сметана": "сметана",
    "творог": "творог", "сыр": "сыр", "йогурт": "йогурт",
    "сливки": "сливки", "масло": "масло", "яйцо": "яйца",
    "хлеб": "хлеб", "батон": "батон", "булочка": "булочки",
    "мука": "мука", "сахар": "сахар", "соль": "соль",
    "рис": "рис", "гречка": "гречка", "макароны": "макароны",
    "мясо": "мясо", "курица": "курица", "рыба": "рыба",
    "фарш": "фарш", "колбаса": "колбаса", "сосиска": "сосиски",
    "сок": "сок", "вода": "вода", "чай": "чай", "кофе": "кофе",
    "печенье": "печенье", "конфета": "конфеты", "шоколад": "шоколад",
    "мыло": "мыло", "шампунь": "шампунь", "салфетка": "салфетки",
    "подгузник": "подгузники", "пакет": "пакеты",
}


@lru_cache(maxsize=1)
def analyzer():
    """Load the bundled Russian dictionary once per server process."""
    return MorphAnalyzer(lang="ru")


def key(value):
    return value.casefold().replace("ё", "е")


@lru_cache(maxsize=1024)
def canonical_name(word):
    candidates = {
        PRODUCT_NAMES[key(parsed.normal_form)]
        for parsed in analyzer().parse(word)
        if parsed.is_known and parsed.tag.POS == "NOUN"
        and key(parsed.normal_form) in PRODUCT_NAMES
        and not ({"Name", "Surn", "Patr", "Geox"} & parsed.tag.grammemes)
    }
    # Different noun readings are allowed only when they agree on one product.
    return next(iter(candidates)) if len(candidates) == 1 else None


def normalize_voice_name(name):
    """Normalize known single-word products, preserving everything else verbatim."""
    if not re.fullmatch(r"[А-Яа-яЁё]{1,200}", name):
        return name
    canonical = canonical_name(key(name))
    if canonical is None or key(canonical) == key(name):
        return name
    if name.isupper():
        return canonical.upper()
    return canonical.capitalize() if name.istitle() else canonical
