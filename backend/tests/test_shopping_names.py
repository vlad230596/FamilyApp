import pytest

from familyapp.shopping_names import normalize_voice_name


@pytest.mark.parametrize(("spoken", "expected"), [
    ("овощей", "овощи"), ("овощи", "овощи"), ("Овощей", "Овощи"),
    ("ОВОЩЕЙ", "ОВОЩИ"), ("моркови", "морковь"), ("молока", "молоко"),
    ("помидоров", "помидоры"), ("помидор", "помидоры"), ("яблок", "яблоки"),
    ("яиц", "яйца"), ("макарон", "макароны"), ("хлеба", "хлеб"),
    ("лука", "лук"), ("сливок", "сливки"), ("мыла", "мыло"),
    ("свеклы", "свёкла"), ("свёклы", "свёкла"), ("Хлеб", "Хлеб"),
])
def test_known_product_forms(spoken, expected):
    assert normalize_voice_name(spoken) == expected
    assert normalize_voice_name(expected) == expected


@pytest.mark.parametrize("name", [
    "средство для посуды", "2 пачки молока", "Молоко 3,2%", "сливочного масла",
    "зелёных яблок", "Coca-Cola", "Фейри", "Миф", "ВкусВилл", "грабли",
    "неведомопродукта", "стали", "молока и хлеба", "овощей,", "яиц 10 шт",
])
def test_complex_unknown_or_ambiguous_names_are_preserved(name):
    assert normalize_voice_name(name) == name
