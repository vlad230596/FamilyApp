# FamilyApp Flutter

Flutter client for the FamilyApp restriction calendar.

## Run Locally

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter pub get"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter run -d chrome --dart-define API_BASE_URL=http://127.0.0.1:5055"
```

## Checks

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter analyze"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter test"
```

The app uses three primary destinations: calendar, full restriction history, and
settings. The calendar opens on today by default and shows the selected-day
restriction count. Child names, child icons, and restriction type management
live in settings.
