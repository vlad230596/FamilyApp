# Iteration 1 Plan

## Goal

Create the first working foundation for FamilyApp: a Flask backend, a Flutter
app shell, and a minimal restriction calendar flow that can be tested locally.

The iteration should prove the core product loop:

1. A parent admin can create children.
2. A parent admin can create a time-bounded restriction for a child.
3. A parent admin can view active and past restrictions.
4. A parent admin can extend or cancel an active restriction.

## Scope

### Backend

- Create the `backend/` project using Flask and Poetry.
- Configure SQLite for local development.
- Add basic project structure for app setup, routes, persistence, and domain
  logic.
- Implement initial domain models:
  - `ParentAdmin`
  - `Child`
  - `Restriction`
- Implement restriction statuses:
  - `active`
  - `cancelled`
  - `expired`
- Add API endpoints for:
  - listing children;
  - creating a child;
  - listing restrictions;
  - creating a restriction;
  - extending a restriction;
  - cancelling a restriction.
- Add basic tests for restriction creation, extension, cancellation, and status
  behavior.

### Flutter App

- Create the `app/` Flutter project.
- Move the Flutter helper script to `app/scripts/setup_vscode_flutter_env.ps1`.
- Configure Material 3.
- Add Riverpod for state management.
- Build a phone-first Russian UI for:
  - child list;
  - child creation;
  - restriction list;
  - restriction creation;
  - restriction extension;
  - restriction cancellation.
- Support web runs for local development testing.

### Developer Experience

- Add backend run and test instructions.
- Add Flutter run and test instructions using the helper script.
- Add `.gitignore` entries for local databases, environment files, build output,
  and editor/system noise.
- Keep secrets and private family data out of the repository.

## Out Of Scope

- Authentication and real user accounts.
- Yandex Alice integration.
- Push notifications.
- Production deployment.
- Cloud database setup.
- Advanced recurring chores or household schedules.
- Complex permission management beyond the initial `ParentAdmin` concept.

## Suggested Milestones

### 1. Repository Foundation

- Create `backend/` and `app/` directories.
- Add baseline `.gitignore`.
- Move Flutter helper into the app-level scripts folder.
- Document local commands.

### 2. Backend Skeleton

- Initialize Poetry project.
- Add Flask and test dependencies.
- Add app factory and health endpoint.
- Configure SQLite for local development.
- Add first backend tests.

### 3. Domain And API

- Add models and persistence for parent admins, children, and restrictions.
- Implement create/list/update flows for restrictions.
- Add tests for restriction lifecycle behavior.

### 4. Flutter Skeleton

- Create Flutter app.
- Enable Material 3.
- Add Riverpod.
- Add basic navigation and Russian UI structure.
- Verify the app runs on web.

### 5. Restriction Calendar Flow

- Connect Flutter screens to backend endpoints.
- Implement creating, viewing, extending, and cancelling restrictions.
- Add visible empty, loading, error, and success states.

### 6. Stabilization

- Run backend tests.
- Run Flutter tests or analysis.
- Run the app locally for manual verification.
- Update documentation with any final command changes.

## Acceptance Criteria

- Backend can be started locally.
- Backend tests pass.
- Flutter app can be started locally through the helper script.
- A parent admin can manage children and restrictions through the app UI.
- Restriction lifecycle behavior is covered by backend tests.
- No secrets, tokens, local databases, or private production data are committed.
