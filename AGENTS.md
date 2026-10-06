# AGENTS.md

This file defines how agents should work in the FamilyApp repository.

## Product Context

FamilyApp is a family coordination project for shared household routines,
schedules, and responsibilities.

The first feature is a restriction calendar for children. A parent admin should
be able to add a restriction for a specific child and time period, extend an
existing restriction, or cancel it. A later Yandex Alice integration may let
children ask when they are allowed to watch cartoons again.

The user-facing interface is Russian. Repository documentation and code comments
are English.

## Agent Workflow

- Communicate with the project owner in Russian.
- Make straightforward implementation changes autonomously.
- Ask before architectural decisions, destructive operations, broad refactors, or
  changes that affect unrelated areas.
- Agents may create focused commits and push changes as part of an explicitly
  requested task or release. A request to publish a release authorizes committing
  and pushing the changes needed for that release, creating its version tag,
  and publishing it through the existing release workflows without asking again.
- Include only changes within the authorized task scope in each commit and release.
- Do not revert, overwrite, or remove user changes unless explicitly requested.
- Keep changes focused on the current task.
- Use release tags in `MAJOR.MINOR.PATCH` format without a `v` prefix, for example `0.1.0`.
- Before larger edits, briefly explain the intended approach.
- After changes, run relevant checks and, when applicable, start the app so it can
  be tested locally.

## Repository Structure

Use this structure unless the project owner decides otherwise:

- `backend/` - Python Flask backend.
- `app/` - Flutter application.

The application is tested on desktop web during development, but the primary
runtime target is Android phones.

## Backend Guidelines

- Use Python with Flask.
- Use Poetry for dependency and environment management.
- Use SQLite as the initial database.
- Keep domain logic separate from HTTP route handlers where practical.
- Add tests for business rules and API behavior when implementing backend logic.
- Do not introduce additional backend frameworks, database engines, task queues,
  or service layers without asking first.

## Flutter Guidelines

- Use Flutter with Material 3.
- Use Riverpod for state management unless the project owner decides otherwise.
- Build and test for web during development, while keeping Android phone usage as
  the primary design target.
- Prefer Russian UI text.
- Keep UI code responsive and suitable for phone screens first.
- Do not add large UI frameworks or code generation tools without asking first.

## Flutter Commands

Run Flutter and Dart commands through the repository helper so the agent uses the
same SDK path as VS Code. The helper reads `dart.flutterSdkPath` from VS Code
settings JSON and adds that SDK's `bin` directories to the current process
environment. It intentionally does not guess SDK locations from `PATH`,
`FLUTTER_ROOT`, or common install folders; if VS Code is not configured, Flutter
commands should fail until the SDK path is configured.

The current helper is `scripts/setup_vscode_flutter_env.ps1`. When the Flutter
application source tree is created, move this helper to:

```powershell
app/scripts/setup_vscode_flutter_env.ps1
```

Run Flutter and Dart commands from the Flutter app folder with:

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter test"
```

Agents may run Flutter commands through this helper, including `flutter create`,
`flutter pub add`, `flutter test`, and local development runs.

## Domain Language

Use `restriction` as the English domain term for punishment-related features.

Initial domain concepts:

- `User` - an independent account with login and password, optionally linked to
  members in one or more families.
- `Family` - a private group with its own members, restrictions, and settings.
- `Member` - a participant in one family with a role: `parent` or `child`. A member
  may be linked to a user; members without a user cannot sign in.
- `Invitation` - one-time, time-limited permission to join a family or link a user
  to an existing member. Its role is chosen by a parent.
- Parents (all equal) manage family settings and restrictions. Children see
  their own data and can do limited actions.
- `Chore` - a household task with a schedule (daily or chosen weekdays) and an
  optional duty member per weekday. Planned, see `docs/iteration-3-plan.md`.
- `ShoppingItem` - an item on the shared shopping list with an urgency. Planned.
- `Restriction` - a time-bounded restriction assigned to a child.
- Restriction fields should include child, start date, end date, reason, status,
  and audit information for who created or changed it.
- Restriction status should support active, cancelled, and expired states.
- Extending or cancelling a restriction should preserve enough history to explain
  what happened later.

## Privacy And Security

- Treat children and family data as private.
- Do not commit secrets, tokens, credentials, local database files, or personal
  production data.
- Use environment variables or `.env` files for secrets; keep local `.env` files
  out of version control.
- Do not log sensitive child or family data unless it is necessary for local
  debugging and clearly non-production.
- Future Yandex Alice credentials and webhook secrets must not be stored in the
  repository.

## Future Integration

Yandex Alice integration is planned but should not be implemented yet unless
explicitly requested. The integration will be broad: restriction status, who is
on duty today, marking duties as done, and the shopping list. Keep all business
logic on the backend (the Flutter app is just one client) and keep the API
voice-friendly so a future Alice skill can use it.

Voice commands cannot tell who is speaking, so Alice may read anything and add
shopping items, but a duty marked done by voice is only a draft until a parent
confirms it in the app. Restrictions and ratings are changed only in the app.

The backend is deployed in Docker on a separate VDS shared with other projects.
