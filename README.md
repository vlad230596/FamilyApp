# FamilyApp

FamilyApp is a small family coordination app for household routines, schedules,
and shared responsibilities.

The first feature is a restriction calendar for children: a parent can add,
extend, cancel, and review color-coded time-bounded restrictions, such as when a
child is allowed to watch cartoons again.

## Stack

- Backend: Python, Flask, Poetry, SQLite
- App: Flutter, Material 3, Riverpod
- Primary target: Android phones
- Development target: local web testing

See [Iteration 1 Plan](docs/iteration-1-plan.md),
[Iteration 2 Plan](docs/iteration-2-plan.md), and
[Iteration 3 Plan](docs/iteration-3-plan.md) for the roadmap.

See [Deployment](DEPLOYMENT.md) for GitHub Releases, the shared VDS ingress,
and interactive setup of the initial parent accounts.

See [Alice integration](docs/alice.md) for the read-only voice webhook, family
account linking, server configuration, and Yandex Dialogs console settings.

## Local Development

Backend:

```powershell
cd backend
poetry install
poetry run flask --app familyapp run --port 5055
poetry run pytest
```

Flutter web:

```powershell
cd app
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter pub get"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter run -d chrome --dart-define API_BASE_URL=http://127.0.0.1:5055"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter test"
```

## Current App Flow

- Sign-in: anyone can register an independent account, then create a family or
  accept an invitation. Creating a family makes the user a parent in that family.
  All parents are equal. Settings allow switching families or creating another.
- Invitations: a parent chooses a role or an existing member without an account.
  The recipient registers or signs in and enters the code. Codes expire after
  48 hours and can only be used once. Parents cannot change another user's password.
- Migration: existing members and restrictions are preserved in a legacy family;
  existing credentials move to independent accounts. Old sessions are revoked.
  Legacy members without credentials are never claimed by a public registration.
  If a legacy family has no account, its access must be restored locally by the
  operator; there is no public endpoint to claim it.
- `Календарь`: primary screen with today's date selected by default, colored
  markers, selected-day restriction count, details, and an optional child filter.
- `Ограничения`: full restriction history, including active, expired, and
  cancelled items.
- `Задачи`: recurring checks with one responsible member, a start date,
  an interval of 1-365 calendar days or selected weekdays, a reminder time,
  and an IANA timezone. Parents create, edit, reassign, and pause tasks.
  Only the responsible member can answer Yes or No; both answers finish that
  occurrence. No answer remains distinct from No. History preserves the
  original title, actor, schedule revision, and answer timestamp.
- `Настройки`: own account (change password, sign out), family members with
  roles and app access, and reusable restriction type management.

Parents manage everything. Children see only their own restrictions and cannot
change restrictions, types, or members.

## Regular Task Reminders

- Android reminders use `flutter_local_notifications`, without Firebase or a
  server queue. Only the assigned member's selected family is scheduled.
- Enable notifications from the Tasks tab. Exact alarm permission is optional:
  without it Android may delay delivery. Notification contents are private on
  the lock screen. Yes/No actions open the app and submit an authenticated answer;
  internet access is required to save it. Failed answers remain available in
  the task list and are not queued offline.
- A sync schedules the next 60 days, capped at the nearest 200 notifications.
  Open the app regularly to replenish the schedule. Sync runs on opening,
  resuming, manual refresh, and every minute while the app is in the foreground.
  There is no background network sync yet. Reboot restores scheduled alarms.
- Changes on another phone take effect only after this phone syncs. Old alerts
  cannot submit answers after reassignment, pause, or a schedule edit. Signing
  out or choosing another family cancels local reminders.
- The timezone belongs to the task, so travel does not move its reminder time.
  Android defaults to the device timezone; web defaults to Moscow for UTC+3
  and UTC otherwise. The timezone is editable in the form.
- Web supports task management and answers, but does not schedule notifications.
- The list offers the latest due check; older unanswered checks are not rolled
  into a debt. Ratings, parent confirmation, and fairness statistics are deferred.

API: `GET|POST /api/chores`, `POST /api/chores/<id>`,
`GET|POST /api/chores/<id>/answers`, `GET /api/chores/reminders`.
Creating and editing require a parent; answering requires the assigned member.
Answers include `occurrence_date`, boolean `answer`, and current `revision`.

Restriction creation supports reusable colored types and one-off custom
restrictions. The form uses a start date plus duration in days, weeks, or months
and keeps entered values visible when validation fails.
