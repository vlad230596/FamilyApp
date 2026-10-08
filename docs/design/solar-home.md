# Solar Home: proposed FamilyApp redesign

Status: owner-approved direction, implemented in Flutter. The original HTML is
the interactive reference proposal. Open `solar-home.html` directly in a browser; no build, server,
network connection, or external dependencies are required. Keep the file in the
repository because it references the existing brand SVG by relative path.

## Direction

Build on the existing approved house icon: navy `#233656`, sunflower `#F6C445`,
and coral `#E8553E`. White cards sit on a warm neutral background `#F6F5F1`.
Use navy for text and primary controls, yellow for friendly emphasis and active
navigation, and coral for restriction accents. Coral body text uses the darker
`#A83527` variant. Avoid a green seed tint across all surfaces.

The UI/UX Pro Max search returned a minimal, high-contrast system. Its generic
marketing layout, green secondary color, and Latin font pairing are unsuitable
for this Russian household app. The proposal adapts its hierarchy and interaction
guidance to the existing brand, rather than adopting those recommendations.
The prototype uses Segoe UI/system fonts with Cyrillic support. A production
font choice can be evaluated during implementation without adding a dependency.

## Information architecture

Five destinations: Today, Tasks, Calendar, Shopping, Family. Desktop uses a navy
sidebar; phones use bottom navigation. This is a proposed UI reorganization,
not a change to domain rules or backend architecture.

- Today becomes the opening screen: daily progress, duties, parent confirmation,
  restriction summaries, and a link to the shopping list.
- Tasks separates duties from Yes/No checks. Duty completion remains pending
  until parent review; checks have no confirmation or debt. Fairness balances,
  schedules, away periods, performers, markers, and ratings remain available
  through dedicated panels/details. Positive balance means debt.
- Calendar combines restrictions and their history. A week selector and period
  bar replace text-heavy summaries; the availability date is prominent. A full
  month/year picker remains required in production.
- Shopping uses compact checkbox-like rows grouped by urgency. Category is
  secondary text; history, list management, recurrence, and purchase metadata
  open separately. All three existing urgency levels are preserved.
- Family groups participants, invitations, personal reminders, restriction
  types, schedules, and family settings. Account and family switching remain
  required in the production implementation.

## Progressive disclosure

Show title, relevant member, status, and one immediate action in each row.
Open explanations, audit history, schedule configuration, timezone, performer,
marker, and rating in details. Keep short status words alongside visual states;
icons and color never replace essential meaning. Restrictions use a period bar,
not a reward/progress score. Completion counters exclude pending duties.

The child preview shows Max's own tasks and restrictions and personal settings.
Parent confirmation and management actions are hidden. Actual privacy enforcement
must remain on the backend; this demo's role toggle is only a presentation tool.
Child access to shared shopping is retained in the concept and must be checked
against existing permissions during implementation.

## Components and implementation constraints

- Retain Flutter, Material 3, Riverpod, the existing APIs, and domain logic.
- Use semantic color tokens instead of scattered screen-specific colors.
- Use Material icons in Flutter, consistently outlined at 24 logical pixels.
- Use a 4/8 spacing rhythm, 16/20/24 card padding, and 18–24 corner radii.
- Keep main Android tap targets at least 48 logical pixels.
- Use clear selected/pressed states, visible focus, accessible names, native
  controls, and reduced-motion support.
- Phone: one column; tablet: contextual two-column layout; desktop: sidebar
  and bounded content width. Respect system safe areas and text scaling.
- Only the light theme is proposed here. A dark theme would need separate
  color and contrast review before implementation.

## Prototype scope

Working demo interactions: five destinations, parent/child preview, duty review
and rating, completion submission, Yes/No answers, task creation, week selection,
restriction extension/cancellation, shopping addition/purchase/undo, urgency and
category changes, recurrence settings, and contextual detail dialogs.

New restriction creation validates the form but does not mutate the sample
dataset. Invitations, notification preferences, full calendars, absence editing,
and persistent audit trails are explanatory previews. Sample data is fictional;
all edits are in memory and reset on reload. There are no backend calls.

The owner approved the visual direction, navigation, and information density.
Flutter implementation preserves existing APIs, authorization, and in-progress
changes. Account setup and sign-in now use the house icon as well.

The production domain treats the restriction end date as inclusive. Flutter
therefore displays availability from the following day; the original HTML's
exclusive midnight dates are only illustrative. Today's progress excludes
pending duty submissions, counts both Yes and No check answers, and shows
checks planned for later today without enabling an early answer.

## Validation

Browser smoke checks passed in installed Chrome for all five destinations at
375, 390, 768, 1024, and 1440 CSS pixels with no horizontal document overflow or
JavaScript errors. Checked duty confirmation/rating, child action visibility,
Yes/No responses, restriction end-date selection/extension/cancellation,
shopping addition/purchase/undo/category/urgency, escaped user input, Escape
closing a modal, landscape, and reduced motion. Larger body text was also
checked for document overflow; this is not a complete accessibility audit or
Flutter text-scaling test. Desktop and phone screenshots accompany the HTML.

Flutter validation: all 42 tests pass; the analyzer reports no issues; the web
release build succeeds. Widget coverage includes narrow portrait, landscape,
expanded desktop, 2x text, reduced motion, check/duty progress, notification
destinations, and preserving the selected calendar month/day across resizing.
Launcher/PWA icon dimensions and Android XML were checked. Android device
verification has not been performed.

The built web app was also exercised in Chrome against an isolated temporary
Flask database: parent and child login, all five destinations at 375/768/1440
pixels, shopping entry, check selection, a real duty confirmation, and child
data/action visibility passed without JavaScript errors. Preview fixtures and
credentials are temporary and are not part of the repository.
