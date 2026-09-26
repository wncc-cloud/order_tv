# TV Error Logs — Plan

**Status:** proposed, not implemented.
**Spans two repos:** `oder_tv` (the Android TV kiosk) and `billing_cafe` (the POS/KDS
app, which already owns the `clientLogs`/"Bug Logs" system this plan extends). This
same file is kept in both repos' roots (`oder_tv/TV_ERROR_LOGS_PLAN.md` and
`billing_cafe/phase_plan/tv_error_logs.md`) so either repo's context has the full
picture.

## Goal

The kitchen TV kiosk (`oder_tv`) already writes a live-status heartbeat doc to
`businesses/why-not-cafe/devices/{deviceId}` (see `TV_STUCK_DISPLAY_FIX_PLAN.md`),
but that only shows *current* state — if a TV was stuck 3 hours ago and already
recovered or got restarted, there's no record of it. The ask: when the kiosk hits a
stream/parse error, or auto-restarts itself, record it somewhere durable, so it can
be checked later (not just observed live), and clean it up automatically the same
way the café already keeps its Firestore usage on the free Spark plan.

Requested UI shape: the existing "Bug Logs" button becomes a small hub — two cards,
**"TV Error Logs"** and **"KOT App Logs"** — each opening a list of just that
category. Deletion: same manual cleanup pattern already in place, extended to a
7-day cutoff for these too (matching the existing bug-log retention, not the 10-day
figure floated earlier in this planning conversation — 7 days is what's already
proven safe on the free plan).

## Key design decision: reuse `clientLogs`, don't build a second collection

The original draft of this plan (see conversation history) proposed a brand new
`deviceEvents` collection with its own repository, its own Firestore rules block,
and its own cleanup call. Once the actual `billing_cafe` code was checked, that
turned out to be unnecessary — `businesses/{id}/clientLogs` already does everything
needed:

- It's already a durable, typed, Admin-readable log of client-side problems
  (`type` field currently `ERROR` / `STUCK` / `DISPLAY_ERROR`).
- It already has an **unauthenticated create path** for exactly this situation — an
  unauthenticated kiosk display with no staff login
  (`firebase/firestore.rules:1634-1658`, currently scoped to the *web*
  `?display=kitchen` route's `source: 'KitchenDisplayScreen'`).
- It already has server-enforced expiry (`expireAt <= request.time + 8 days`,
  writer sets exactly 7) and an Admin-only manual cleanup button
  (`ClientLogRepository.deleteOldLogs()`, wired into
  `settings_screen.dart`'s `_runCleanup()`).

So instead of a second parallel system, this plan **adds one new `type` value**
(`'TV_ERROR'`) and **one new `source` value** (`'AndroidTvKioskDisplay'` — deliberately
distinct from the existing `'KitchenDisplayScreen'` source, which is the *web*
kitchen display on `?display=kitchen`, a different device from the physical Android
TV kiosk this repo builds) to the collection that already exists. Net effect:

- **No new Firestore collection.**
- **No new repository class.**
- **No new cleanup code at all** — `deleteOldLogs()` already sweeps every expired
  doc in `clientLogs` regardless of `type`, so TV error logs get cleaned up by the
  exact same existing button, automatically, the moment they start being written
  with the same `expireAt` shape everything else in this collection already uses.
- Only the **rules enum** and the **UI's list-hub split** are new.

## Changes required

### 1. `billing_cafe` — Firestore rules (`firebase/firestore.rules`)

Extend the existing anonymous `clientLogs` create rule (currently lines
~1634-1658) to accept the new type/source pair, alongside the existing
`DISPLAY_ERROR`/`KitchenDisplayScreen` case:

```
allow create: if request.auth == null
  && request.resource.data.keys().hasOnly([
       'type', 'source', 'message', 'stackTrace', 'userId',
       'userEmail', 'userAgent', 'appUrl', 'flavor', 'createdAt',
       'expireAt', 'schemaVersion', 'deviceId'
     ])
  && (
       (request.resource.data.type == 'DISPLAY_ERROR'
         && request.resource.data.source in ['CustomerDisplayScreen', 'KitchenDisplayScreen'])
       || (request.resource.data.type == 'TV_ERROR'
         && request.resource.data.source == 'AndroidTvKioskDisplay'
         && request.resource.data.deviceId is string
         && request.resource.data.deviceId.size() <= 64)
     )
  && request.resource.data.message is string
  && request.resource.data.message.size() <= 2000
  && (request.resource.data.stackTrace == null
      || (request.resource.data.stackTrace is string
          && request.resource.data.stackTrace.size() <= 4000))
  && request.resource.data.userId == null
  && request.resource.data.userEmail == null
  && request.resource.data.userAgent is string
  && request.resource.data.userAgent.size() <= 500
  && request.resource.data.appUrl is string
  && request.resource.data.appUrl.size() <= 500
  && request.resource.data.flavor is string
  && request.resource.data.flavor.size() <= 20
  && request.resource.data.schemaVersion == 1
  && request.resource.data.createdAt == request.time
  && request.resource.data.expireAt > request.time
  && request.resource.data.expireAt <= request.time + duration.value(8, 'd');
```

(`deviceId` added as an optional-but-required-for-TV_ERROR field so a log entry can
be traced back to which physical TV box produced it — useful once there's more than
one.) The `allow get`/`allow list: if isAdmin()` lines above it, and the
staff-authenticated `create` block, and `allow update: if false` / the Admin-only
`allow delete`, all stay exactly as they are — nothing else in this match block
changes.

**Note:** since `devices/{deviceId}` was already published as its own separate rule
in this same file (the heartbeat/live-status doc from the earlier plan), this change
is additive to that, not a replacement — the two collections serve different
purposes (`devices` = current state, `clientLogs` = history) and both stay.

### 2. `oder_tv` — write TV_ERROR logs (`lib/services/kitchen_firestore_service.dart`)

Add a small helper, using the exact same field shape `ClientLogRepository._write`
already uses server-side-verified values for (`createdAt` via
`FieldValue.serverTimestamp()`, not a client-computed timestamp — the rule requires
`createdAt == request.time`, which only `FieldValue.serverTimestamp()` satisfies).

**Needs a dedupe window, matching `ClientLogRepository._write`'s existing
`_lastLoggedAt` pattern** — without one, a genuinely flapping connection would spam
one log entry per retry. The kitchen/controls resubscribe backoff already caps at
60-second retries (`kReconnectBackoffSeconds`), so during a sustained outage this
would otherwise write one nearly-identical `TV_ERROR` entry every 60 seconds
indefinitely (a multi-hour outage → dozens of duplicate rows cluttering the "TV
Error Logs" list). The existing KOT-side dedupe uses a 30-second window because its
errors aren't rate-limited by a backoff schedule the way this is; here a 5-minute
window (comfortably longer than the 60s retry ceiling) is enough to collapse a
sustained outage into one entry every 5 minutes instead of one every 60 seconds,
while still capturing a *new*, different error promptly:

**Also needs the pruning step the original has, not just the dedupe check** — `ClientLogRepository._write` calls `_pruneExpired(now)` before every write specifically to keep its dedupe map bounded; a straight port that copies the *lookup* but drops the *prune* would leak one map entry per distinct error message ever seen, for the lifetime of the process (this kiosk is designed to stay up for weeks/months between restarts, unlike a KOT web session that reloads far more often — so this matters more here, not less):

```dart
final Map<String, DateTime> _lastTvErrorLoggedAt = {};
static const _tvErrorDedupeWindow = Duration(minutes: 5);

Future<void> _logTvError(String deviceId, String message) async {
  final dedupeKey = message.length > 200 ? message.substring(0, 200) : message;
  final now = DateTime.now();
  _lastTvErrorLoggedAt.removeWhere((_, at) => now.difference(at) >= _tvErrorDedupeWindow);
  final last = _lastTvErrorLoggedAt[dedupeKey];
  if (last != null && now.difference(last) < _tvErrorDedupeWindow) return;
  _lastTvErrorLoggedAt[dedupeKey] = now;

  try {
    await _firestore.collection('businesses/$kBusinessId/clientLogs').add({
      'type': 'TV_ERROR',
      'source': 'AndroidTvKioskDisplay',
      'deviceId': deviceId,
      'message': message.length > 2000 ? message.substring(0, 2000) : message,
      'stackTrace': null,
      'userId': null,
      'userEmail': null,
      'userAgent': 'android-tv-kiosk',
      'appUrl': 'android-tv://kitchen-display',
      'flavor': 'production',
      'createdAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      'schemaVersion': 1,
    }).timeout(_kHeartbeatCallTimeout);
  } catch (_) {
    // Best-effort, same reasoning as every other write in this file — a
    // failure to log a bug must never itself become a blocking error.
  }
}
```

Call sites split into two different treatments — don't apply one pattern to both:

- **The 4 routine error call sites are synchronous callbacks**, so each must wrap
  the call in `unawaited(...)` (same convention already used for `_runHeartbeat` in
  this file): kitchen listener `onError` and its parse-error `catch` block, and the
  same pair for controls —
  `unawaited(_logTvError(deviceId, 'kitchen stream: $error'))` /
  `unawaited(_logTvError(deviceId, 'kitchen parse: $e'))`, etc.
- **The restart-event call is the opposite — it must be `await`ed, not fired and
  forgotten.** It's exposed as a separate public `logRestartEvent(String reason)`
  wrapper (see below), called from `kitchen_display_screen.dart` right before
  `AppRestart.restart()` fires. Bounded by the same timeout, so the write gets a
  real chance to reach the server before the process dies seconds later — same
  reasoning already applied to the telemetry write ordering in
  `TV_STUCK_DISPLAY_FIX_PLAN.md`.

`deviceId` needs threading through. **Decided, not left open:** since the proposed
public API is `logRestartEvent(String reason)` — no `deviceId` parameter — the
service *must* store it as an instance field, not just thread it through call
sites. Concretely, in `kitchen_firestore_service.dart` (currently at line 220,
`void startHeartbeat({required String deviceId})`):

```dart
String? _deviceId; // new field, alongside the other heartbeat state

void startHeartbeat({required String deviceId}) {
  _deviceId = deviceId;
  _heartbeatTimer?.cancel();
  _heartbeatTimer = Timer.periodic(kHeartbeatResubscribeInterval, (_) {
    unawaited(_runHeartbeat(deviceId));
  });
}

Future<void> logRestartEvent(String reason) async {
  final deviceId = _deviceId;
  if (deviceId == null) return; // heartbeat never started — nothing to attribute this to
  await _logTvError(deviceId, 'restart: $reason');
}
```

In practice `_deviceId` is always set by the time a restart can fire (`startHeartbeat`
is called synchronously in `initState`, before any watchdog tick or long-press is
possible), but the null-guard costs nothing and avoids a hard crash if that ordering
ever changes.

**Exact call-site change needed in `kitchen_display_screen.dart`:**
- `_maybeAutoRestart()` (currently ends at line 188 with `await AppRestart.restart();`)
  — already an `async` function, so just add
  `await _service.logRestartEvent('watchdog: stale for over 8 minutes');` on the
  line immediately before it.
- The long-press handler (currently lines 201-204):
  ```dart
  _longPressTimer ??= Timer(const Duration(seconds: 3), () {
    _longPressTimer = null;
    AppRestart.restart();
  });
  ```
  This callback is a **synchronous** `void Function()` today — it needs to become
  `async` to `await` the log write first:
  ```dart
  _longPressTimer ??= Timer(const Duration(seconds: 3), () async {
    _longPressTimer = null;
    await _service.logRestartEvent('manual long-press');
    await AppRestart.restart();
  });
  ```
  (A `Timer`'s callback type accepts an `async` function literal fine — its
  returned `Future` is simply not awaited by `Timer` itself, but the `await`s
  *inside* the callback body still run in order before `AppRestart.restart()`
  fires, which is exactly what's wanted here.)

### 2.5 `billing_cafe` — extend the existing automated rules tests (do this, not just eyeball the rule)

**This was missing from every earlier draft of this plan and is the single most
important addition from this review pass.** `firebase/rules-tests/rules.test.js`
already has a real, extensive automated suite exercising the *exact* anonymous
`clientLogs` create rule this plan modifies — section 60 ("Client bug logging:
clientLogs anonymous display-screen path (Decision 2B)", starting ~line 4615)
includes adversarial tests like "any OTHER source value... is denied — the core
anti-spoofing property" and "type ERROR (instead of DISPLAY_ERROR) is denied — can't
forge a staff-attributed entry via the anonymous path." This is exactly the kind of
regression this rule change could introduce if the rewritten boolean structure has
a subtle error — and this codebase's own convention (see the rules file's own
"confirmed empirically... in this suite's own rules-tests" comments elsewhere) is to
verify exactly that way, not by manual re-reading. **Run this suite before
publishing the rule, not after** — `cd firebase/rules-tests && npm test` (needs the
Firestore emulator; `npm run emulator` in a separate terminal first, matching
whatever this repo's existing rules-test setup doc already says).

Add these new cases into section 60's existing block, reusing its `anon` context
and `validAnonLog` helper already in scope:

```js
const validTvErrorLog = (overrides = {}) => ({
  type: "TV_ERROR", source: "AndroidTvKioskDisplay", deviceId: "abc123",
  message: "kitchen stream: unavailable", stackTrace: null, userId: null,
  userEmail: null, userAgent: "android-tv-kiosk", appUrl: "android-tv://kitchen-display",
  flavor: "production", createdAt: serverTimestamp(),
  expireAt: Timestamp.fromMillis(Date.now() + 7 * 24 * 60 * 60 * 1000),
  schemaVersion: 1,
  ...overrides,
});

await check(
  "Anonymous: a valid TV_ERROR create with source AndroidTvKioskDisplay succeeds",
  setDoc(doc(anon, `businesses/${BIZ}/clientLogs/log_anon_tv`), validTvErrorLog()),
  "allow"
);

await check(
  "Anonymous: TV_ERROR with any other source is denied — same anti-spoofing "
    + "property as the DISPLAY_ERROR case above, for the new branch",
  setDoc(
    doc(anon, `businesses/${BIZ}/clientLogs/log_anon_tv_spoofed_source`),
    validTvErrorLog({ source: "CustomerDisplayScreen" })
  ),
  "deny"
);

await check(
  "Anonymous: source AndroidTvKioskDisplay paired with type DISPLAY_ERROR "
    + "(mismatched type/source pair across the two OR'd branches) is denied",
  setDoc(
    doc(anon, `businesses/${BIZ}/clientLogs/log_anon_tv_wrong_type`),
    validAnonLog({ source: "AndroidTvKioskDisplay" })
  ),
  "deny"
);

await check(
  "Anonymous: TV_ERROR missing deviceId entirely is denied",
  setDoc(
    doc(anon, `businesses/${BIZ}/clientLogs/log_anon_tv_no_deviceid`),
    (() => { const d = validTvErrorLog(); delete d.deviceId; return d; })()
  ),
  "deny"
);

await check(
  "Anonymous: TV_ERROR with an oversized deviceId (>64 chars) is denied",
  setDoc(
    doc(anon, `businesses/${BIZ}/clientLogs/log_anon_tv_long_deviceid`),
    validTvErrorLog({ deviceId: "x".repeat(65) })
  ),
  "deny"
);

// Regression check: the pre-existing DISPLAY_ERROR path (tested just above in
// this same section, before this plan's change) must still behave identically
// now that the rule's boolean structure has an added OR branch.
await check(
  "Anonymous: existing DISPLAY_ERROR/CustomerDisplayScreen path still succeeds "
    + "after the TV_ERROR branch was added alongside it",
  setDoc(doc(anon, `businesses/${BIZ}/clientLogs/log_anon_regression_display`), validAnonLog()),
  "allow"
);
```

I traced through the two trickiest adversarial cases by hand against the proposed
rule text (mixing `type: 'TV_ERROR'` with an existing legitimate `source`, and vice
versa) and both correctly deny — but "I traced it by hand" is exactly the kind of
confidence this test suite exists to replace with something that actually runs
against the real rules engine.

Confirmed directly (not assumed) before writing the snippets above: `BIZ` in this
file is `"biz1"`, a fake emulator-only business id — the new test cases already use
the `${BIZ}` template variable, not a hardcoded `'why-not-cafe'`, so they slot into
the existing pattern correctly. Also confirmed `npm test`'s final line
(`` `${pass} passed, ${fail} failed` ``) is backed by a real
`process.exit(fail > 0 ? 1 : 0)` — a failure genuinely fails the run (checkable by
exit code, not by scrolling a very long console log), and section 60 sits inside one
of the `run1()`-`run20()` functions `run()` actually calls, not orphaned code.

### 3. `billing_cafe` — repository filter (`lib/services/client_log_repository.dart`)

`fetchRecent` currently fetches everything. Add an optional type filter so each
hub card's screen only queries its own subset:

```dart
Future<List<ClientLogEntry>> fetchRecent({int limit = 200, List<String>? types}) async {
  Query<Map<String, dynamic>> query = _logs.orderBy('createdAt', descending: true);
  if (types != null) query = query.where('type', whereIn: types);
  final snap = await query.limit(limit).get();
  return snap.docs.map((d) => ClientLogEntry.fromFirestore(d.id, d.data())).toList();
}
```

(A composite index will almost certainly be required for `type` + `orderBy(createdAt)`
— there's no existing query in this codebase combining the two. **Expect the first
time either filtered card is opened to show an error screen with a "create index"
link from Firestore, not data** — that's normal, not a bug; click the link, wait
~1-2 minutes for the index to build, then retry. Add the resulting index definition
to `firebase/firestore.indexes.json` afterward so it's captured for future
deploys/emulator runs, not just the console's ad-hoc copy.)

**`ClientLogEntry` needs a `deviceId` field added, or it's write-only.** The model's
`fromFirestore` factory (`lib/models/client_log_entry.dart`) only reads a fixed set
of named fields — as this plan currently writes it, `deviceId` would land in
Firestore and pass the rules check, but be silently invisible in the UI (the
factory simply never looks at it). Add:
```dart
final String? deviceId; // + constructor param + `deviceId: _str(data['deviceId']),` in fromFirestore
```
and show it in `bug_logs_screen.dart`'s row subtitle/detail dialog for TV_ERROR
entries — this is the one field that lets you tell two physical TVs apart once
there's more than one, so it's worth wiring all the way through now rather than
leaving it write-only until "later."

### 4. `billing_cafe` — UI split (`lib/screens/admin/bug_logs_screen.dart`)

- Rename the existing list-rendering widget/logic into a reusable
  `_LogListView`-style piece (or a second screen `bug_log_list_screen.dart`) that
  takes a `types` filter and a title, so both cards reuse one implementation
  instead of duplicating the `ListView.builder`/dialog code.
- Add a new top-level `BugLogsScreen` (the thing the nav icon opens) that shows two
  `Card`s:
  - **"TV Error Logs"** → pushes the list view filtered to `types: ['TV_ERROR']`.
  - **"KOT App Logs"** → pushes the list view filtered to `types: ['ERROR', 'STUCK', 'DISPLAY_ERROR']`
    (i.e. everything that isn't `TV_ERROR` — the existing behavior, just scoped).

  **Keep this an explicit whitelist — don't "future-proof" it with
  `whereNotIn`/`isNotEqualTo: 'TV_ERROR'`.** That looks like the more robust choice
  (auto-includes any future new KOT-side type without an edit here), but Firestore
  requires an inequality filter (`!=`/`not-in`) to be the *first* `orderBy` field
  when combined with one — so `.where('type', isNotEqualTo: 'TV_ERROR').orderBy('createdAt')`
  would be rejected, and the only way to satisfy it
  (`.orderBy('type').orderBy('createdAt')`) sorts all same-typed entries together
  *before* sorting by recency, breaking the card's actual intent ("most recent
  across all KOT types," not "grouped by type, recent within each group"). Plain
  `==`/`whereIn` (what both cards actually use) has no such restriction, so the
  explicit list is correct as written — just remember to add any genuinely new
  KOT-side `type` value to this list by hand if one is ever introduced.
- No change needed to `counter_home_screen.dart`'s nav wiring (`bug_report_outlined`
  icon → `BugLogsScreen`) — same entry point, it just now opens a hub instead of a
  flat list.
- `_typeColor()`'s `switch` has no `TV_ERROR` case — it'll fall through to the
  default outline color, which won't crash but looks unstyled. Add an explicit
  color (something visually distinct from `ERROR`'s red, e.g. `Colors.blueGrey`)
  while touching this file.

### 5. `billing_cafe` — cleanup

**No code change.** `ClientLogRepository.deleteOldLogs()` and `previewCleanup()`
already operate on the whole `clientLogs` collection regardless of `type` — once
TV error logs start landing in this same collection with the same `expireAt` shape,
the existing "Data Cleanup" button in Settings sweeps them automatically, same as
it already does for `ERROR`/`STUCK`/`DISPLAY_ERROR`. The confirm dialog's copy
(`'...plus N bug/error logs older than 7 days'`) already reads correctly without
edits, since it's already generic across `type`.

## File-by-file task list

**`oder_tv`:**
- [ ] `lib/services/kitchen_firestore_service.dart` — add `_logTvError`, wire into
      the 4 existing error call sites, add public `logRestartEvent(reason)`.
- [ ] `lib/screens/kitchen_display_screen.dart` — call `logRestartEvent(...)` right
      before both `AppRestart.restart()` call sites (watchdog + long-press).

**`billing_cafe`:**
- [ ] `firebase/firestore.rules` — extend the anonymous `clientLogs` create rule's
      type/source check as shown above.
- [ ] `firebase/rules-tests/rules.test.js` — add the 6 new test cases from section
      2.5 into the existing section 60 block. **Run `npm test` against the emulator
      and confirm it passes before publishing the rule anywhere** — this is not
      optional polish, it's how this exact rule block is already verified in this
      codebase's own established practice.
- [ ] `app/lib/models/client_log_entry.dart` — add `deviceId` field + parsing.
- [ ] `app/lib/services/client_log_repository.dart` — add `types` param to
      `fetchRecent`.
- [ ] `app/lib/screens/admin/bug_logs_screen.dart` — split into hub + reusable list
      view (or a new sibling screen for the list); add a `TV_ERROR` case to
      `_typeColor()`; show `deviceId` in the row/detail dialog for TV entries.
- [ ] `firebase/firestore.indexes.json` — add composite index once Firestore's
      console surfaces the exact one it wants (expected on first run, see above).
- [ ] Re-publish `firestore.rules` (same Console flow as the `devices/{deviceId}`
      rule from the earlier plan) — only after the rules-tests pass locally.

## Testing checklist

- **Run `firebase/rules-tests` (`npm test` against the local emulator) and confirm
  every case passes, including the new TV_ERROR cases and the DISPLAY_ERROR
  regression case — before publishing the rule to the real project.** This is the
  one step most likely to be skipped under time pressure and the one most likely to
  catch a real mistake in the rewritten boolean logic.
- Trigger a stream error on the kiosk (e.g. temporarily point it at a
  non-existent Firestore project, or airplane-mode the device) — confirm a
  `TV_ERROR` doc appears in `clientLogs` within a few seconds.
- Trigger the watchdog restart (or long-press) — confirm a `TV_ERROR` restart-event
  doc appears before the process dies (this is the one racy write — verify it
  actually lands, don't just assume the timeout was enough).
- Open Bug Logs in `billing_cafe` as an Admin — confirm the two-card hub appears,
  each card opens the correctly-filtered list, and TV entries never show up under
  "KOT App Logs" or vice versa.
- Run the existing Settings → Data Cleanup flow — confirm the preview count
  includes TV error logs older than 7 days, and they're actually gone afterward.
- Confirm a non-Admin (Cashier/Kitchen) still cannot read `clientLogs` at all
  (existing `allow get/list: if isAdmin()` is untouched, but worth a quick check
  after the rules edit).

## Open questions

- Card copy/wording for the hub ("TV Error Logs" / "KOT App Logs" as given here,
  or different wording preferred).
- Whether `logRestartEvent` should also fire for something other than
  errors/restarts (e.g. "device came back after being stuck") — out of scope for
  now per the "record only error [+ restart]" decision in this planning
  conversation, but worth a comment if it should widen later.

## Residual risk (documented, not fixed — inherited from an existing pattern)

**Device clock drift could reject a write, or shorten/lengthen its real retention.**
`expireAt` here is computed client-side (`DateTime.now().add(Duration(days: 7))`),
same as the existing KOT-side `ClientLogRepository._write` already does — this isn't
a new risk this plan introduces. But the rule caps it at `request.time +
duration.value(8, 'd')`, checked against the *server's* clock, not the device's. An
Android TV box is a worse-case device for this than a staff phone/laptop: no
reliable RTC battery on cheap hardware, so after a power cut it can boot with a
wildly wrong date until NTP resync completes. If the kiosk's clock is far enough
ahead of real time, the write gets rejected outright (silently caught by the
existing `try`/`catch` — no crash, just a missing log entry for whatever error
prompted it); if it's behind, the entry expires earlier than the intended 7 days.
Not fixing this now since it matches an already-accepted pattern elsewhere in
`billing_cafe` — flagging so a "why didn't this log appear" investigation someday
thinks to check the device's system clock, not just Firestore rules/quotas.
