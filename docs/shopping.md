# Shopping lists

Release 0.5.0 adds shopping to the Flutter app with multiple shared lists per family.
Parents create and rename lists and choose the main list. All signed-in family
members can add purchases, mark items bought, and use purchase history and returns.

Existing items and purchase history migrate to a main list named "\u0413\u043b\u0430\u0432\u043d\u044b\u0439".
Exactly one list is main. Alice reads and adds items only in the current main list;
changing it does not require relinking Alice. Duplicate names merge only within
their list. Scheduled and manual returns preserve the original list.

## API

- `GET /api/shopping`: main-list items, purchases, all list metadata and `list_id`.
- `GET /api/shopping?list_id=N`: selected-list items and purchases.
- `POST /api/shopping/lists`: create a list (`name`, optional `is_main`). Parent only.
- `POST /api/shopping/lists/N`: rename or make main (`name`, optional `is_main`). Parent only.
- `POST /api/shopping`: add an item; optional `list_id` defaults to the main list.
- Existing buy and purchase-return endpoints retain their behavior.

Lists and item operations are isolated by family. List deletion is not exposed.
