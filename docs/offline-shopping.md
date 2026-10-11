# Offline shopping

Shopping lists support offline reads, adding items, and marking items as bought.
The device must have signed in and fetched shopping data online at least once.
All lists are fetched together, so switching lists does not need a connection.
List management and manual purchase returns still require the server.
Other application features retain their existing online behavior.

## Local state

The existing `flutter_secure_storage` dependency stores one JSON document per
user/family/member. The document contains the last server snapshot, pending
commands, unresolved conflicts, notices, and the last synchronization time.
This is intended for small household lists, not an unbounded offline database.
The saved account is tied to the saved session token and removed on logout.
Shopping commands remain isolated by owner, allowing the same account to sign
back in without losing unsent purchases. They never appear for another account.

The UI projects pending commands over the last server snapshot. It confirms an
edit only after the local document has been written successfully. Network
requests do not block additional local edits. The banner shows local operation,
pending command count, and last synchronization time. A previously uncached
account or list cannot be opened offline.

## Protocol

- `GET /api/shopping/snapshot` returns all family lists and their snapshots in
  one transaction, including up to 200 purchases per list.
- `POST /api/shopping/sync` applies one command: `add`, `buy`, or `resolve`.
  Every command includes an immutable `operation_id`, explicit `family_id`,
  and `occurred_at`. Additions specify a list; purchases specify `item_key` or
  the `add_operation_id` of an earlier offline addition.
- Server receipts are stored in the same transaction as the change, scoped to
  family and member. Repeating an ID with the same payload returns its receipt;
  reusing it with different data fails. Receipts have no automatic expiry, as
  deleting them could make a long-offline device apply a command twice.
- The client removes a command only after persisting its receipt effects and
  a fresh server snapshot together. Commands remain immutable; acknowledgement
  of an addition stores its item identity separately for the local projection.
- HTTP validation/access errors leave the command visibly blocked until the
  user explicitly removes it. Network/server failures preserve the queue and
  retry later. Authentication failure signs the user out and preserves the
  owner's shopping document for subsequent authenticated access.

`item_key` is a UUID identity for an individual shopping item occurrence.
Purchases retain it as `source_item_key`. Re-adding or returning the same name
creates a new occurrence; delayed purchases cannot remove it even if SQLite
has reused the old integer ID. Existing online purchase routes also preserve
this identity. Schema changes run automatically at backend startup.

## Merge rules

- Different items combine naturally.
- Same normalized name in the same list merges into one item with the higher
  urgency. An existing nonempty category is preserved. Offline duplicates do
  not escalate urgency merely because they are retried.
- Buying an already purchased occurrence does not add another history entry.
  Equal return periods produce a notice. Different return periods produce a
  conflict with explicit choices: keep the server period or apply the local
  period. A return already performed or cancelled cannot be rescheduled by
  conflict resolution. A changed server period is checked again before applying
  the user's choice.
- Purchase time is the locally recorded action time, in UTC. The server accepts
  timezone-aware dates from 2000 onward and at most five minutes into the future.
  Return periods start from that purchase time, not the later synchronization.

## Scheduling

Foreground synchronization runs at startup, after an edit, on app resume,
on manual refresh, and every five seconds while offline or commands are pending.
Requests have a ten-second timeout. Account/family/member identity is checked
before sending commands.

Android additionally schedules a connected-network one-off WorkManager task
and a 15-minute recovery task. Android controls their actual execution time.
Workers replay commands without writing the shopping document: this prevents
background acknowledgement from overwriting new foreground edits. Receipts make
foreground/background replay safe. The next foreground sync reconciles the
local document. Logout/family selection invalidates and cancels those workers.

Web supports local data while the app is loaded and persists it across launches
when the app itself can load. Serving the Flutter application assets for a full
offline browser reload is outside this feature; no PWA service worker is added.
Browser storage requires a secure context (HTTPS or localhost).

## Verification

Backend tests cover duplicate receipts, concurrent purchases, same-name merges,
new occurrences, dependent offline additions, family isolation, return conflicts,
all-list snapshots, and invalid purchase dates.
Flutter tests cover the 50-item/5-purchase scenario, restart, lost responses,
local write failure, concurrent edits during sync, background replay, owner
isolation, cached login, rejected sessions, and the offline UI at phone,
landscape, and desktop sizes with large text and reduced motion.

For manual Android testing: fetch a list, enable airplane mode, add an item,
mark five positions bought, close/reopen the app, then restore connectivity.
Check the pending count reaches zero and purchase history has exactly five new
entries. Test background delivery separately because OS scheduling differs
from foreground retry behavior.
