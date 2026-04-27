# FamilyApp

FamilyApp is a small family coordination app for household routines, schedules,
and shared responsibilities.

The first feature is a restriction calendar for children: a parent can add,
extend, cancel, and review time-bounded restrictions, such as when a child is
allowed to watch cartoons again.

## Stack

- Backend: Python, Flask, Poetry, SQLite
- App: Flutter, Material 3, Riverpod
- Primary target: Android phones
- Development target: local web testing

See [Iteration 1 Plan](docs/iteration-1-plan.md) and
[Iteration 2 Plan](docs/iteration-2-plan.md) for the current roadmap.

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
