# Iteration 3 Plan

## Goal

Grow FamilyApp from a restriction calendar into a shared family tool: every
family member signs in, household chores and duties are tracked fairly, and the
family keeps one shared shopping list. Everything must stay usable by a future
Yandex Alice skill.

Stages, in order:

1. Accounts and roles (done).
2. Chores and duties with history and fairness statistics.
3. Shared shopping list.
4. Local push reminders.

Alice integration comes after these stages.

## Product Decisions

### Accounts

- Every family member is a `Member` with a role: `parent` or `child`.
- All parents are equal. There is no public sign-up: the first parent registers
  on a fresh server, and parents create accounts for everyone else.
- A member may have no login (for example, a small child). Such a member still
  exists for restrictions and duties.
- Children see only their own restrictions and cannot change restrictions,
  types, or members.
- Changing a password signs the member out on all other devices.

### Chores And Duties

- Daily rituals ("check that the dishwasher is running") and weekday duties are
  one entity: a chore with a schedule (daily or chosen weekdays) and an optional
  duty member per weekday.
- Marking a chore done stores the performer separately from who marked it,
  because adults usually mark a child's duty.
- A child's "done" needs parent confirmation. Parents rate a duty on three
  levels: bad, normal, great. In the first version, ratings are used only for
  statistics and do not affect fairness.
- Fairness: the weekday schedule stays fixed. A day when nobody was home
  ("away") is not counted as debt. A parent can set an away period for the whole
  family. A missed duty while at home counts as debt. The app shows the balance
  and suggests who owes a day.
- Each chore has its own reminder time.

### Shopping List

- One shared, persistent list. Any member can add items.
- Urgency: urgent, this week, background. Optional category for grouping.
- Background items become "this week" after about 30 days. "This week" never
  escalates to urgent automatically.
- Adding an item that is already on the list raises its urgency instead of
  creating a duplicate (important for voice input).
- Bought items go to history. On purchase the app offers "return to the list in
  N days?".

### Reminders

- Push reminders are local: the app schedules them from data it has synced.
  No server push and no Firebase.
- A change made on another phone reaches the reminder only after the app syncs
  (on open and periodically in the background).

### Alice

- Alice may read anything and add shopping items.
- A duty marked done by voice is a draft until a parent confirms it.
- Restrictions and ratings are changed only in the app.
- The backend runs in Docker on a VDS, so it can be reached over HTTPS later.

## Stage 1: Accounts And Roles

### Backend

- `members` table replaces `children` and `parent_admins`. On first start the
  legacy rows are copied: children keep their ids, parent admins get new ids,
  and restriction audit columns are remapped. Legacy tables are kept untouched.
- `sessions` table stores SHA-256 hashes of random bearer tokens. Logout and
  password changes revoke sessions.
- Passwords are hashed with Werkzeug (`generate_password_hash`).
- Endpoints:
  - `GET /api/auth/status` - `{setup_required}`.
  - `POST /api/auth/setup` - first parent; allowed only while nobody has a
    password. Claims the migrated legacy admin if there is one.
  - `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/me`.
  - `GET /api/members`, `POST /api/members` (parent),
    `POST|PUT /api/members/<id>` (parent),
    `POST /api/members/<id>/credentials` (parent, or the member themselves).
- Every `/api/*` endpoint except auth status, setup, and login requires
  `Authorization: Bearer <token>`. Management endpoints require a parent.

### App

- Setup and login screens; the token is stored with `flutter_secure_storage`.
- Settings: "My account" (change password, sign out) and "Family" (members,
  roles, access). Children see the family list read-only.
- Children do not see restriction management actions or the child filter.

### Known Limits

- No login rate limiting yet. Add it before exposing the server publicly.
- The first-parent setup is open until someone registers. Complete it right
  after deploying a fresh server.
