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

The Solar Home interface uses five destinations: Today, Tasks, Calendar,
Shopping, and Family. Phones use bottom navigation; expanded windows use a
sidebar. Today summarizes household duties, checks, parent confirmations, and
restrictions using the signed-in member's existing permissions. The calendar
and its restriction history remain available separately from the daily summary.
Family contains account, member, invitation, and restriction type settings.

The theme uses navy, sunflower yellow, and coral from the existing house icon.
The same brand asset is bundled for Flutter and used by Android launcher icons,
the web favicon, and PWA icons. See [branding](../docs/branding.md) and the
[approved design proposal](../docs/design/solar-home.md).
