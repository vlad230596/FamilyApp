# Iteration 3 Plan

## Goal

Grow FamilyApp from a restriction calendar into a shared family tool: every
family member signs in, household chores and duties are tracked fairly, and the
family keeps one shared shopping list. Everything must stay usable by a future
Yandex Alice skill.

Original stage order, with current status (2026-10-07):

1. Accounts and roles (done).
2. Chores and duties with history and fairness statistics (implemented).
3. Shared shopping list (implemented).
4. Local push reminders, including Android background synchronization (implemented;
   real-device delivery and battery-optimization checks remain manual).

The first read-only Alice restriction adapter is present in uncommitted working
tree changes. Live deployment and Yandex console/speaker verification are not
confirmed. Broader duty and shopping integration remains planned. See
[Alice integration](alice.md) for the adapter's scope and verification steps.

## Product Decisions

### Accounts

- A `User` is an independent account. Public registration creates only an
  account, without granting access to an existing family.
- A `Member` belongs to one `Family`, with a role of `parent` or `child`, and
  may be linked to a user. A user may belong to several families.
- All parents are equal. Creating a family makes its creator a parent there.
  Parents invite other users with a selected role or link them to an existing
  member without an account. Invitations expire after 48 hours and are single-use.
- A member may have no account (for example, a small child). Such a member still
  exists for restrictions and duties, but cannot be assigned regular checks.
- Children see only their own restrictions and cannot change restrictions,
  types, or members.
- Changing a password signs the member out on all other devices.

### Chores And Duties

- Household chores have two workflows: regular checks (direct Yes/No) and duties
  (daily or chosen weekdays, with an optional assignee per weekday). They share
  the Tasks tab but preserve their different completion rules.
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

#### Implemented First Slice: Regular Checks

- The Tasks tab supports interval-based checks (every N days, 1-365) and chosen
  weekdays, with a start date, reminder time, and an explicit IANA timezone.
- Each check has exactly one responsible member with an app account. Only that
  member receives reminders and submits the Yes/No answer. Parents manage the
  definitions; children may answer their assigned checks directly.
- Yes and No both close that occurrence; an unanswered check remains separate.
  No repeat reminder after No. Immutable answers and definition snapshots
  preserve history through schedule edits, reassignment, and pauses.
- Android schedules local reminders for up to 60 days (nearest 200 alerts),
  refreshed on app open/resume and while foregrounded. Notification actions
  open the app to authenticate and save the answer. Web supports forms and
  answers only. Android also refreshes in the background through WorkManager.
- Duty ratings, parent confirmation, away periods, and fairness belong to the
  separate duties workflow; they are never applied to regular Yes/No checks.

#### Implemented Duties Workflow

- Parents create duties, choose active weekdays and assignees (including members
  without accounts), and configure a reminder time and IANA timezone.
- New duties start today or later. Edits and pauses apply from tomorrow or the
  initial future start, whichever is later. Start date and timezone remain fixed.
  Revisions preserve original daily assignments, titles, and reminder settings.
- A child submits only their own assigned duty, as themselves. Parents may mark
  any family member as the performer. Child submissions are pending until a parent
  confirms with bad/normal/great or rejects them for resubmission. Every submission
  and review preserves an audit snapshot. Confirmed occurrences cannot be overwritten.
- Balance covers all duties: a past unconfirmed assigned occurrence adds 1 debt
  day; a confirmed substitution adds 1 to the assignee and subtracts 1 from the
  performer. Unassigned duties have no debt or compensation. Today's open duties
  do not count as missed; a past pending submission counts until confirmed.
- Active family away periods exclude both missed duties and substitution credit.
  Cancelling an away period restores those dates to the calculation. Ratings
  affect statistics only. The highest positive balance is suggested for compensation;
  equal balances use a stable member-id order. The schedule is never auto-rotated.
- Children see their assigned occurrences and their own statistics. Parents see
  the family balance, confirmation queue, history by date, and schedule management.

### Shopping List

- One shared, persistent list. Any member can add items.
- Urgency: urgent, this week, background. Optional category for grouping.
- Background items become "this week" after about 30 days. "This week" never
  escalates to urgent automatically.
- Adding an item that is already on the list raises its urgency instead of
  creating a duplicate (important for voice input).
- Bought items go to history. On purchase the app offers "return to the list in
  N days?".
- Names are normalized for case, whitespace, and Russian e/yo. A duplicate raises
  urgency by at least one level without lowering an existing urgent item.
- Automatic escalation and scheduled returns are applied on the next shopping
  API request, without a server job queue. A return merges with an existing item
  without raising its urgency unnecessarily. Returns can be cancelled or triggered
  immediately from purchase history. History preserves all purchases; the current
  UI/API lists the latest 200.

### Reminders

- Push reminders are local: the app schedules them from data it has synced.
  No server push and no Firebase.
- A change made on another phone reaches the reminder only after the app syncs.
  Current sync runs on open, resume, refresh, and every minute in the foreground.
  Android WorkManager requests a sync every 15 minutes when a network is available.
  Android controls actual timing and may defer work during Doze, force-stop, or
  vendor battery restrictions. Background work uses secure stored credentials;
  work input and notification payloads contain no token. Failed network requests
  keep the last alarms and request retry. Logout/family selection invalidate work.
  A generation check discards stale responses and cancels a just-scheduled stale alert.

### Alice

- Alice may read anything and add shopping items.
- A duty marked done by voice is a draft until a parent confirms it.
- Restrictions and ratings are changed only in the app.
- Docker deployment and HTTPS ingress configuration are available. The first
  adapter reads restrictions only; voice duty drafts and shopping writes are planned.

## Stage 1: Accounts And Roles

### Backend

- `members` table replaces `children` and `parent_admins`. On first start the
  legacy rows are copied: children keep their ids, parent admins get new ids,
  and restriction audit columns are remapped. Legacy tables are kept untouched.
- `users`, `families`, and `invitations` separate accounts from memberships.
  Legacy credentials and family data migrate without allowing public registration
  to claim legacy members. A legacy family without an account requires local recovery.
- `user_sessions` stores SHA-256 hashes of random bearer tokens. Logout and
  password changes revoke sessions.
- Passwords are hashed with Werkzeug (`generate_password_hash`).
- Endpoints:
  - `POST /api/auth/register` - independent account registration.
  - `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/me`.
  - `GET /api/members`, `POST /api/members` (parent),
    `POST|PUT /api/members/<id>` (parent),
    `POST /api/members/<id>/credentials` (account owner only).
  - `POST /api/families`, `POST /api/families/<id>/select`.
  - `POST /api/invitations` (parent), `POST /api/invitations/accept`.
- Every `/api/*` endpoint except registration and login requires
  `Authorization: Bearer <token>`. Management endpoints require a parent.

### App

- Registration and login screens, family creation/selection, and invitation
  acceptance; the token is stored with `flutter_secure_storage`.
- Settings: "My account" (change password, sign out) and "Family" (members,
  roles, access). Children see the family list read-only.
- Children do not see restriction management actions or the child filter.

### Login Protection And Known Limits

- Login accepts up to 10 attempts per normalized login and 30 per direct client
  address per 60-second window, counting successful and failed attempts. Limits
  persist in SQLite across workers and restarts. Exceeding a limit returns HTTP
  429 with a Russian message and `Retry-After`; existing sessions remain usable.
- Forwarded address headers are not trusted. Behind a reverse proxy, users may
  share the address budget. Registration has separate limits of 10 attempts per
  address and 3 per normalized login per minute, also persisted in SQLite.
- The old public setup/status endpoints are no longer part of the account flow.

## API For Duties And Shopping

- `GET|POST /api/duties`, `POST /api/duties/<id>` (definitions managed by parents).
- `POST /api/duties/occurrences/<id>/complete` with `performer_member_id` and
  parent-only `rating`; `POST .../review` with `approved` and `rating` (parent).
- `GET /api/duties/occurrences/<id>/history` (family and child visibility enforced).
- `POST /api/away-periods`, `POST /api/away-periods/<id>/cancel` (parent).
- `GET|POST /api/shopping`, `POST /api/shopping/<id>/buy` with optional
  `return_in_days` (1-3650), `POST /api/shopping/purchases/<id>/return`, and
  `POST /api/shopping/purchases/<id>/cancel-return` (any family member).
- `GET /api/chores/reminders` returns the nearest 200 combined check/duty alerts
  over 60 days for the authenticated member. Duty alerts open the duties screen;
  only check alerts offer Yes/No actions.

## Remaining Work

Broader Alice integration is the next feature stage and is intentionally excluded
from this implementation wave. Physical Android verification should cover background
refresh after app closure, permission denial, reboot, logout/family switching during
sync, and edits made from a second device. Features are implemented locally; this
status does not claim a production release or verified live deployment.
