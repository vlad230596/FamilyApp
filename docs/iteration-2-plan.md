# Iteration 2 Plan

## Goal

Improve the restriction workflow so the app feels closer to daily use by a
parent: restrictions are quick to add, validation happens inside the form, child
management moves out of the main flow, and the calendar becomes the primary way
to understand what is happening today and in the near future.

The iteration should prove the next product loop:

1. A parent admin can manage children from settings, not from the main screen.
2. A parent admin can choose a restriction type, create a reusable type, or enter
   a one-off custom restriction.
3. A parent admin can create a restriction without losing form data when
   validation fails.
4. A parent admin can set a start date and duration in days, weeks, or months.
5. A parent admin can see today's restrictions by child at a glance.
6. A parent admin can inspect a color-coded calendar of restrictions.

## Product Decisions

- Child list editing is a rare administrative task and should move to a
  settings area.
- Restriction type is a first-class concept. A reusable type has a name and a
  color. A concrete restriction references a type when possible.
- A concrete restriction may still use a one-off custom name for exceptional
  cases without adding it to the reusable type list.
- Restriction color comes from its type. One-off custom restrictions receive a
  color for that restriction only.
- Restriction creation should focus on start date and duration. Direct end date
  editing can remain available as an advanced or fallback option if needed.
- The main screen should prioritize operational status: what applies today,
  which children are restricted, and the calendar overview.

## Scope

### Backend

- Add a `RestrictionType` domain concept.
- Store restriction type fields:
  - id;
  - name;
  - color;
  - active/archived flag or equivalent lightweight visibility control;
  - audit timestamps.
- Extend `Restriction` storage with:
  - optional `restriction_type_id`;
  - `custom_type_name` for one-off restrictions;
  - `color` or enough serialized data for the frontend to render the effective
    color reliably.
- Add API endpoints for:
  - listing restriction types;
  - creating a restriction type;
  - archiving or hiding a restriction type if it is no longer used;
  - creating a restriction with either a type or a custom one-off name;
  - listing today's active restrictions;
  - listing restrictions for a date range for calendar rendering.
- Keep existing restriction lifecycle behavior for extension, cancellation, and
  expired status.
- Add backend validation so a restriction cannot be created without either a
  reusable type or a custom name.
- Add tests for:
  - reusable restriction type creation;
  - restriction creation from a reusable type;
  - restriction creation with a custom one-off type;
  - validation errors for missing type/name and invalid dates/duration;
  - today's active restrictions;
  - date-range calendar queries.

### Flutter App

- Rework navigation around daily usage:
  - main overview;
  - calendar;
  - settings.
- Move child list creation/editing into settings.
- Add a settings screen for restriction types:
  - list existing types;
  - create a new type;
  - choose or auto-assign a color;
  - hide/archive a type when appropriate.
- Rework the restriction creation form:
  - child selector;
  - restriction type dropdown;
  - option to add a new reusable type from the form;
  - option for a one-off custom restriction name;
  - start date picker;
  - duration controls for days/weeks/months;
  - computed end date preview;
  - optional note/reason text.
- Keep validation inside the dialog/screen:
  - do not close the form while validation fails;
  - keep all entered data after backend validation errors;
  - show field-level errors where practical;
  - show form-level errors only for cross-field or server problems.
- Update the child overview:
  - color each child row/card based on active restrictions;
  - show restrictions active today;
  - handle multiple active restrictions with multiple color markers.
- Add a color-coded calendar:
  - month view for phone screens;
  - days colored by active restrictions;
  - selected day details below the calendar;
  - legend or chips for restriction colors;
  - clear empty state for days without restrictions.

### Developer Experience

- Keep local backend port at `5055`.
- Keep Flutter web launch config using `API_BASE_URL=http://127.0.0.1:5055`.
- Update README instructions after command or navigation changes.
- Run backend tests after backend changes.
- Run Flutter `analyze` and `test` after app changes.

## Out Of Scope

- Authentication and real user accounts.
- Yandex Alice integration.
- Push notifications.
- Production deployment.
- Multi-family support.
- Recurring restrictions.
- Complex permissions beyond the current parent-admin assumption.
- Full calendar sync with external providers.

## Suggested Milestones

### 1. Backend Restriction Types

- Add database table and persistence helpers for restriction types.
- Add type list/create API endpoints.
- Add default seed types if useful for local testing.
- Add backend tests for type creation and validation.

### 2. Restriction Creation Model

- Update restriction creation to accept reusable type or one-off custom name.
- Add color resolution for each restriction.
- Add duration-based request handling if the backend should compute end dates.
- Add tests for typed and custom restrictions.

### 3. Settings Navigation

- Move child management out of the main tabs into settings.
- Add settings entry point in the app shell.
- Add restriction type management UI in settings.

### 4. Robust Restriction Form

- Replace the current simple dialog with a validated form.
- Preserve entered values after validation errors.
- Add duration controls and end date preview.
- Support adding a reusable type from the form.

### 5. Today Overview

- Add backend query or frontend filtering for restrictions active today.
- Show today's restrictions per child.
- Color child rows/cards from active restriction colors.
- Handle multiple active restrictions without visual ambiguity.

### 6. Calendar View

- Add month calendar UI.
- Load restrictions by date range.
- Color days by restriction colors.
- Show selected-day restriction details.

### 7. Stabilization

- Run backend tests.
- Run Flutter analysis and tests.
- Manually verify local web flow:
  - create child in settings;
  - create reusable restriction type;
  - create restriction using duration;
  - create one-off custom restriction;
  - see today's restrictions;
  - inspect calendar colors.
- Update documentation with final behavior and commands.

## Acceptance Criteria

- Child creation and editing are available from settings rather than the main
  daily workflow.
- A restriction can be created from a reusable type with a color.
- A restriction can be created with a one-off custom name and color.
- The add restriction form does not close when validation fails and does not lose
  entered data.
- Restriction duration can be entered in days, weeks, or months with a visible
  computed end date.
- The child overview shows active restrictions for today.
- Child overview coloring reflects active restriction colors.
- Calendar view shows restrictions by color and selected-day details.
- Backend tests pass.
- Flutter `analyze` and tests pass.
