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
- `Настройки`: own account (change password, sign out), family members with
  roles and app access, and reusable restriction type management.

Parents manage everything. Children see only their own restrictions and cannot
change restrictions, types, or members.

Restriction creation supports reusable colored types and one-off custom
restrictions. The form uses a start date plus duration in days, weeks, or months
and keeps entered values visible when validation fails.
