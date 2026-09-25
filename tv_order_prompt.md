# Plan: Native Android TV Kitchen Display (workaround for the white-screen bug)

## Background

`cafecountrysidekot.web.app/?display=kitchen` shows a blank white screen on the
Android TV's kiosk browser app, even though it works fine in Chrome on the same
device and disabling SSL certificate checks didn't fix it. Leading cause: this
project's Flutter SDK (3.44.1) has no non-WebAssembly renderer anymore — every
`flutter build web` output requires WebAssembly support in the browser, and the
kiosk app's embedded WebView engine most likely doesn't have (working) WASM support,
even though the device's separately-updated Chrome app does. See `.wolf/buglog.json`
bug-196 and `.wolf/cerebrum.md` (2026-08-27 Key Learnings entry) for the full
diagnostic trail.

Wrapping the same URL in a native app's WebView would NOT fix this — `webview_flutter`
renders through Android's System WebView, almost certainly the same engine already
failing. The actual fix is a **native Flutter Android app that reimplements just the
kitchen display screen using real Flutter widgets and a direct Firestore read** — no
WebView, no browser engine, no WebAssembly dependency at all.

This is lower-risk than it sounds: `KitchenDisplayScreen` doesn't run complex queries —
it listens to ONE Firestore document, and that document already allows **public,
unauthenticated reads** (`allow read: if true` in `firebase/firestore.rules`). No
Firebase Auth needed.

- Document: `businesses/why-not-cafe/public/kitchenDisplay` →
  `{ orders: [{orderNumber, items: [{name, quantity}], readySince}], updatedAt }`
- Pause switch: `businesses/why-not-cafe/public/displayControls` →
  `{ kitchenDisplayEnabled: bool, default true if missing }`
- Firebase project: `why-not-cafe-prod` (see `app/lib/config/firebase_options_pos.dart`)

## Honest confidence check — what this plan can and can't promise

- **The root cause is still not confirmed.** We ruled out TLS/cert trust (disabling
  SSL checks in the kiosk app didn't fix it) and ruled out a device-wide problem
  (Chrome on the same TV renders the site fine). "The kiosk browser's WebView lacks
  working WebAssembly support" is the leading explanation by process of elimination,
  not something we directly confirmed (we asked to check the kiosk app's reported
  WebView/Chromium version and never got that answer). A native app removes the
  *entire category* of failure this points to — no browser engine, no WebAssembly,
  no CanvasKit — which is why it's a strong bet regardless of the exact mechanism.
  It is not a proven fix for a cause we never fully pinned down.
- **Native rendering has a much lower hardware bar than the web build did**, but
  it isn't zero: Flutter's native renderer needs OpenGL ES (universal on Android
  since well before this box was made) or, on Android 10+, Vulkan with an automatic
  OpenGL fallback otherwise. The fact Chrome renders modern, GPU-accelerated pages
  fine on this same device is reassuring circumstantial evidence the hardware/GPU
  drivers are fine — not a guarantee, since Chrome's rendering path isn't identical
  to Flutter's.
- **Unconfirmed device facts**: this TV box's actual Android version and CPU
  architecture (arm64/armv7/x86) are unknown. `flutter build apk --release` builds
  for the common architectures by default, and Flutter's floor is Android 5.0 — very
  likely fine for real hardware from the last decade, but not verified against this
  specific box.
- **The boot-time auto-relaunch is a nice-to-have, not a guarantee.** Some Android
  versions/OEM TV skins restrict apps from starting an Activity in the background
  (even from a `BOOT_COMPLETED` receiver) unless the OS explicitly exempts it. If it
  doesn't fire reliably on this box, fall back to Fully Kiosk's "App Mode" (if
  available) or Screen Pinning, and just power-cycle/relaunch by hand until that's
  set up.
- **The Android TV leanback banner size (320×180px)** came from a secondary-source
  mirror of Android's TV app docs, not the primary developer.android.com page — worth
  a quick cross-check by whoever builds this if the banner doesn't render right in
  the launcher.

None of this changes the recommendation — it's still the strongest option available —
but "will work in one go" isn't something I can honestly promise without testing on
the real device. Budget for at least one round of "build it, sideload it, see what
breaks."

## Step 1 — Build the app (separate project, separate Claude session)

Create a new empty folder, open a fresh Claude Code session there, and paste the
prompt below verbatim. It's self-contained (does not need this repo) and grounded in
this codebase's real schema/config/screen logic — nothing in it is guessed.

One prerequisite: do this on the same computer you're reading this on. `flutter
doctor` already shows a working Android toolchain here (Android SDK 36.1.0, licenses
accepted) — that's what lets the new session actually build and verify the APK
itself per the instructions below, instead of just writing untested code. On a
different, fresh machine, installing Android Studio + the Android SDK would be a
real prerequisite step of its own, not covered by this plan.

> Build a standalone native Flutter Android app called "Why Not Cafe — Kitchen
> Display". It is a NEW, separate project — do not reference or depend on any other
> repo. It is a read-only, unauthenticated, always-on TV kiosk display for a cafe
> kitchen counter.
>
> ## What it shows
>
> It replicates one specific screen from an existing Flutter WEB app (which fails to
> render on this particular Android TV device due to a WebAssembly/CanvasKit
> rendering incompatibility in its embedded browser — this native rebuild sidesteps
> that entirely by using Flutter's native renderer, no WebView, no browser engine
> involved).
>
> ## Firebase setup
>
> Use `firebase_core` + `cloud_firestore` only (NOT `firebase_auth` — this screen
> needs no sign-in, it's a public unauthenticated read, confirmed via the project's
> real `firestore.rules`: `match /public/kitchenDisplay { allow read: if true; }` and
> same for `public/displayControls`).
>
> Initialize Firebase with an explicit `FirebaseOptions` object (do NOT use
> `google-services.json` / the Gradle `google-services` plugin — keep it simple,
> explicit Dart-side config, matching how this project's existing web app does it):
>
> ```dart
> const FirebaseOptions(
>   apiKey: '<ANDROID_API_KEY>',     // placeholder — do NOT reuse the web app's key,
>                                     // see note below
>   appId: '<ANDROID_APP_ID>',       // placeholder — I will paste the real one after
>                                     // registering an Android app in Firebase console
>   messagingSenderId: '871637263829',
>   projectId: 'why-not-cafe-prod',
>   storageBucket: 'why-not-cafe-prod.firebasestorage.app',
> )
> ```
>
> Leave `<ANDROID_API_KEY>` and `<ANDROID_APP_ID>` as obvious placeholder constants I
> can find and replace — I'll get both real values from the Firebase console (manual
> step, not yours to do). IMPORTANT: do not hardcode any other project's/platform's
> API key as a "close enough" substitute — Google Cloud API keys can be locked to a
> specific platform (an Android key is checked against package name + signing
> certificate, a Web key against HTTP referrers), so a key issued for the web app is
> not guaranteed to work from a native Android client even though it's the same
> Firebase project. `messagingSenderId`, `projectId`, and `storageBucket` ARE safe to
> reuse as-is — those are project-level values, not tied to one client app.
>
> Firestore document paths (business id is hardcoded, this app serves one cafe only):
>
> - `businesses/why-not-cafe/public/kitchenDisplay` — the orders payload
> - `businesses/why-not-cafe/public/displayControls` — the pause switch
>
> ## Data model to parse
>
> `public/kitchenDisplay` document shape:
> ```
> {
>   orders: [
>     { orderNumber: int, items: [ { name: string, quantity: int }, ... ], readySince: Timestamp }
>   ],
>   updatedAt: Timestamp
> }
> ```
> A missing document, or a missing `orders` field, both mean an empty list — never
> throw.
>
> `public/displayControls` document shape:
> ```
> { kitchenDisplayEnabled: bool }
> ```
> Missing document OR missing field both mean `true` (fail-open — the display must
> keep working if this doc has never been touched).
>
> Listen to BOTH documents with independent real-time `.snapshots()` listeners (not
> one-shot reads) — the display must update live as orders change, and must react
> live if an admin flips the pause switch.
>
> ## Screen behavior (exact spec — this is a faithful port of the existing web screen)
>
> - Full black background, no app bar, no visible chrome anywhere, no buttons, no
>   touch/tap targets — this is a dead-end passive display, nothing is ever
>   interactive.
> - A local 1-second ticker (`Timer.periodic`) triggers a rebuild every second purely
>   so the "long wait" flag below can update as real time passes, independent of
>   Firestore snapshots.
> - **If `kitchenDisplayEnabled` is false** (paused view): centered pause-circle icon
>   (white at 38% opacity) above the text "Display temporarily unavailable" (white at
>   70% opacity, bold-ish).
> - **Else if `orders` is empty** (idle view): centered text "No orders ready right
>   now" (white at 70% opacity).
> - **Else** (grid view):
>   - Take at most the first 6 orders (`orders` array is already sorted
>     oldest-ready-first by the backend — do not re-sort) for the main tile grid; any
>     orders beyond the first 6 go into a bottom overflow bar instead of being
>     dropped.
>   - Grid columns: 1 column if ≤1 order, 2 columns if ≤4 orders, else 3 columns.
>     Rows = ceil(count / columns). Tiles fill all available space (one order alone
>     should fill the whole screen; two orders split it in half).
>   - Each tile: dark grey (`#1E1E1E`) container, rounded corners, centered content:
>     - `#<orderNumber>` — large bold white text (this is the dominant visual element
>       of the tile, sized relative to the tile's shortest side).
>     - If this order's wait (`now - readySince`) exceeds **5 minutes**: draw a
>       red/error colored border around the tile, and show a red "⚠️ WAITING" line
>       right under the order number.
>     - Then each item as `"<name> × <quantity>"`, white text, one line per item,
>       ellipsis-truncate if too long — never let text overflow/crash the layout.
>   - If there are overflow orders (7th+): a horizontal bar pinned to the bottom of
>     the screen, near-black (`#141414`) background, showing "ALSO READY:" (white
>     70%, bold) followed by a horizontally-scrollable row of `#<orderNumber>` (white,
>     bold) for each overflow order.
>
> ## Fullscreen / Android TV kiosk requirements
>
> - Immersive, edge-to-edge fullscreen on launch — hide the Android status bar and
>   navigation bar entirely (sticky immersive mode via `SystemChrome`), no
>   browser/URL bar exists at all since this isn't a WebView.
> - Force landscape orientation (TV screen).
> - Immersive/fullscreen mode is known to un-hide itself after certain system events
>   (resuming from background, an orientation/metrics change) — don't just set it once
>   in `initState`. Re-apply it from a `WidgetsBindingObserver`'s
>   `didChangeAppLifecycleState`/`didChangeMetrics` too, so the status/nav bars don't
>   silently creep back after the app has been running a while.
> - Keep the screen awake indefinitely — this runs 24/7 on a TV, never sleep/dim (use
>   a current, actively-maintained wakelock package — check pub.dev for whichever one
>   is current/recommended right now, don't assume a specific version).
> - Reconnect gracefully — but don't over-trust the SDK here: Firestore's own
>   reconnection logic covers transient network blips (wifi drop, brief server
>   unavailability) transparently, without the Dart stream ever erroring out. It does
>   NOT self-heal from a terminal error like `permission-denied` (e.g. a bad API key,
>   or a Security Rules mismatch) — that kind of error closes the stream for good, and
>   without doing anything about it the app would sit there forever never receiving
>   another snapshot. So: on `onError` for either listener, after logging it (see the
>   debug overlay section below), resubscribe from scratch after a short delay
>   rather than assuming the existing stream will ever recover on its own — this
>   matters independent of the debug overlay, since a bad credential should not mean
>   "stuck offline forever" once the real API key/appId are in place and a fresh
>   build is installed. Use a simple capped exponential backoff for the retry delay
>   (e.g. 2s, 4s, 8s... up to some max like 60s, resetting back to the short delay
>   once a snapshot actually succeeds) rather than a fixed short interval forever —
>   if the credential turns out to be permanently wrong, retrying every couple of
>   seconds nonstop for days would hammer the API for no benefit.
> - Add Android TV manifest support so the app shows up properly on a TV
>   launcher/app drawer: `android.software.leanback` feature, a
>   `CATEGORY_LEANBACK_LAUNCHER` intent filter on the main activity alongside the
>   normal launcher intent filter, a 320×180 banner drawable, and declare
>   `android.hardware.touchscreen` as NOT required (so it's recognized as
>   TV-compatible).
> - Add a `RECEIVE_BOOT_COMPLETED` broadcast receiver that relaunches this app's main
>   activity on device boot, so the display recovers automatically after a power cut
>   — common for a device that sits behind a kitchen counter with no one around to
>   restart it by hand. This needs the matching Android permission + manifest
>   receiver + a small Kotlin/Java `BroadcastReceiver`.
>
> ## TEMPORARY: on-screen error/debug overlay (delete before final deployment)
>
> This device has no screen I can plug into to read `adb logcat`, so for now every
> error/loading state needs to be visible ON THE TV ITSELF so I can photograph it and
> send it back. Put this whole feature behind one single, obvious constant —
> `const bool kDebugOverlay = true;` at the very top of `main.dart`, with a comment
> saying to flip it to `false` (or delete the overlay code entirely) once the app is
> confirmed working on the real device. Everything below must be gated on that one
> flag so removing it later is a one-line change, not a hunt through the codebase.
>
> When `kDebugOverlay` is true, show a persistent, legible (doesn't need to be
> TV-viewing-distance sized — this is for me to read up close or photograph, so a
> smaller monospace font showing more detail is fine) panel, and catch every one of
> these specific failure modes — don't just wrap the build method in a generic
> try/catch and call it done:
>
> 1. **Firebase.initializeApp() failure** — wrong/placeholder API key or app ID never
>    replaced, no network at boot, etc. Wrap the init call in try/catch; on failure,
>    skip straight to a full-screen error view (there's nothing else to show yet) with
>    the exception's full `toString()`.
> 2. **Firestore stream errors** — both `.snapshots()` listeners (`kitchenDisplay` and
>    `displayControls`) MUST have an `onError` callback, not just a data callback —
>    an unhandled stream error otherwise throws uncaught and the screen would just go
>    blank with zero explanation. Surface the exact error (e.g.
>    `permission-denied` — wrong API key/rules assumption; `unavailable` — no network;
>    anything else) on screen, and keep it visible until a successful snapshot
>    replaces it. This is the same `onError` callback described in the reconnect
>    bullet above (Fullscreen / Android TV kiosk requirements) — one callback per
>    listener that both logs to this overlay AND triggers the backoff-resubscribe,
>    not two separate/competing error handlers.
> 3. **Document parsing failures** — if a document's shape doesn't match what's
>    expected (wrong types, unexpected nulls, a field renamed upstream), the parsing
>    code must not silently produce wrong output or crash uncaught — wrap parsing in
>    try/catch and show a "couldn't parse kitchenDisplay document: <error>" banner
>    rather than either crashing or silently rendering nothing with no clue why.
> 4. **Any uncaught Flutter framework error** — override `FlutterError.onError` to
>    capture widget-build-time errors into the same on-screen log instead of just
>    Flutter's default red/grey error box (which won't be visible/legible on a TV in
>    release mode anyway — release builds usually show a blank grey screen instead of
>    the red error box).
> 5. **Any uncaught async error outside Flutter's own error handling** — wrap the
>    `runApp(...)` call in `main()` inside `runZonedGuarded`, and also set
>    `PlatformDispatcher.instance.onError`, routing both into the same on-screen error
>    log.
> 6. **A permanent connection-status readout**, always visible in debug mode
>    (separate from the error log above): something like
>    "Firebase: ready | kitchenDisplay: live, last update 14:32:05 | displayControls:
>    live" — so I can tell "genuinely no orders right now" apart from "silently stuck,
>    never got a first snapshot" apart from "connected once, then went stale." Include
>    a timestamp of the last successful snapshot for each of the two listeners. Also
>    show whether the document itself EXISTS on the last snapshot
>    (`DocumentSnapshot.exists`), not just whether a snapshot arrived — a wrong
>    collection path (a typo, e.g. singular `business` instead of `businesses`) would
>    still deliver a "successful" empty snapshot with `exists == false` forever, which
>    would otherwise look identical on screen to "correct path, genuinely zero orders
>    right now" (both show the idle view). This is the one bug class that's easy to
>    miss without an explicit exists-flag, since it doesn't throw any error at all.
> 7. **Wakelock / fullscreen-immersive-mode failures must not be fatal** — if either of
>    those platform calls throws (some devices restrict them), catch it, show a small
>    non-blocking warning line in the debug panel, and keep the app running normally —
>    these are nice-to-haves, not core functionality.
>
> Architecture suggestion (don't over-engineer this): a single global
> `ValueNotifier<List<String>>` (or similar) that every catch-site above appends a
> timestamped, prefixed line to (`[INIT]`, `[KITCHEN-STREAM]`, `[CONTROLS-STREAM]`,
> `[PARSE]`, `[FLUTTER-ERROR]`, `[ASYNC-ERROR]`), plus one more notifier/state object
> for the connection-status readout. A top-level `Stack` overlays a scrollable panel
> showing both, on top of whatever the normal screen is currently showing (paused /
> idle / grid) — don't replace the normal UI, overlay on top of it, since seeing both
> at once (e.g. "grid IS showing, AND there's a stale-parse warning") is useful too.
> Cap that log list at something like the most recent 50 entries (drop the oldest when
> full) — this runs 24/7, and if some error ends up looping (e.g. a permanently bad
> API key retrying every few seconds forever), an unbounded log would grow forever and
> could eventually degrade or crash the device from memory growth — the debug feature
> itself becoming a new bug. A capped, repeating log is still perfectly readable for
> diagnosis; you don't need the full history, just the most recent state.
>
> One thing this overlay can't help with: if the app crashes before the Flutter
> engine even starts (a bad native/Gradle build, an immediate JVM-level crash), none
> of this Dart-level code runs at all and the screen will just show nothing or kick
> back to the launcher — that class of failure still needs `adb logcat` from a
> connected computer, this overlay only covers failures after the engine is up.
>
> ## What NOT to do
>
> - Do not add Firebase Auth, do not add any write capability, do not add any way to
>   interact with or dismiss the display — read-only, unauthenticated, non-interactive
>   by design (mirrors the original screen's own explicit "dead end by design"
>   comment).
> - Do not invent extra Firestore fields, screens, or navigation — this app has
>   exactly one screen and does exactly one thing. The debug overlay above is not an
>   exception to this — it's a non-interactive overlay ON that one screen, not a
>   second screen, and it must never intercept touch/input or block the real content.
>
> ## Before you tell me you're done
>
> Don't just write the code and describe what it should do — actually run
> `flutter analyze` and fix every real error it reports (not necessarily every style
> nit, but anything that would stop this from compiling or behaving as specified),
> then actually run `flutter build apk --release` yourself and confirm it completes
> successfully. Do not hand me a project you haven't personally built end-to-end —
> if the build fails, keep fixing it until it doesn't, don't describe the command to
> me as if that were the same thing as having run it.
>
> Also write and run real `flutter test` unit tests for every piece of logic that
> doesn't require a device or a live Firestore connection to verify — these are the
> exact edge cases already spelled out above, so there's no excuse for leaving them
> unverified:
> - Grid column count at the boundaries: 1 order → 1 column, 4 orders → 2 columns, 5
>   orders → 3 columns (the ≤1/≤4/else boundaries, not just one comfortable middle
>   value).
> - The 6-order/7th-order overflow split: exactly 6 orders → no overflow bar, exactly
>   7 → one order in the overflow bar.
> - The 5-minute long-wait threshold at its boundary (e.g. 4:59 → not flagged, 5:01 →
>   flagged).
> - Document parsing: a well-formed document, a document missing the `orders` field
>   entirely, a document that doesn't exist at all (`null` data), and at least one
>   deliberately malformed shape (wrong type for a field) — assert none of these throw,
>   and that the malformed/missing cases resolve to the same safe empty state the
>   original web app's own code documents.
>
> Structure the parsing/grouping/column-math code as small pure functions specifically
> so these are unit-testable without a device or a Firestore connection at all — this
> mirrors how the original web app's own `kitchen_display.dart` is deliberately split
> (pure functions the tests call directly, Firestore only at the very edge) — don't
> bury this logic inside a widget's `build()` method where it can't be tested in
> isolation.
>
> Note on signing: a freshly-created Flutter Android project's release build type
> already defaults to signing with the debug keystore (this is intentional in
> Flutter's own project template, specifically so `flutter build apk --release` works
> out of the box without a real signing key). That's completely fine here — this
> APK is being sideloaded, not published to the Play Store, so don't set up a
> dedicated release keystore/signing config, that would just be extra manual work
> (passwords to generate and remember) for no benefit in this use case.
>
> Note on `minSdkVersion`: leave it at whatever `flutter create` scaffolds by default
> (currently tied to `flutter.minSdkVersion` in the Flutter SDK itself) — don't lower
> it to try to support some hypothetically older device, since going below Flutter's
> own supported floor is unsupported by Flutter and more likely to cause a crash than
> prevent one.
>
> ## Give me a way to test this on my laptop BEFORE I touch the real TV
>
> Sideloading onto the actual Android TV box is slow (build → copy APK → install →
> walk over and look at the screen). I want a fast loop on my laptop first. Give me
> exact, copy-pasteable instructions for the best available option, in this order of
> preference:
>
> 1. **An Android TV emulator**, if the Android SDK on this machine has (or can get)
>    a "Television" system image — Android Studio's AVD Manager has a dedicated "TV"
>    device category (e.g. "Television (1080p)") that emulates the actual Android TV
>    environment, including the leanback launcher, which is the closest thing to the
>    real device without physically having it. If one isn't already installed, tell
>    me the exact steps to create one (or the `sdkmanager`/`avdmanager` commands to do
>    it without opening Android Studio's UI, if that's faster).
> 2. If a TV emulator isn't practical, a **regular Android phone emulator** (any
>    existing AVD, or `flutter emulators --launch <id>`) is still useful for
>    everything except the leanback-launcher/TV-manifest-specific bits — say plainly
>    which parts of the app a phone emulator can't actually validate (TV launcher
>    visibility, the banner, `CATEGORY_LEANBACK_LAUNCHER`) versus what it can (the
>    actual screen logic, Firestore connection, error handling, all of it).
> 3. A **physical Android phone connected over USB** with USB debugging enabled is
>    the simplest option if I have one handy — mention this as a fallback.
>
> Whichever one I use, give me the exact `flutter run` command (not `flutter build`)
> so I get live hot-reload and full stack traces printed directly in the terminal —
> that's strictly more useful for debugging than the on-screen overlay, since the
> overlay exists specifically for the one device that doesn't have a terminal attached
> to it (the real TV). Also tell me plainly: testing on an emulator/phone can confirm
> the app itself is correct, but it cannot confirm or rule out the original
> WebAssembly-in-the-kiosk-browser theory this whole plan is working around — that
> only gets tested by actually installing on the real TV.
>
> ## When you're done
>
> Give me:
> 1. The exact `flutter build apk --release` command you ran, confirmation it
>    succeeded, and where the output APK file landed.
> 2. Confirmation of the `flutter test` results (how many tests, all passing).
> 3. The laptop-testing instructions from the section above.
> 4. A short list of anything you could NOT finish/verify yourself and why (e.g.
>    anything that genuinely needs the real device — I don't expect you to have an
>    Android TV to test on, but everything that doesn't need one should already be
>    verified, not just described).
> 5. The exact file and line of the `kDebugOverlay` flag, and the exact command to
>    rebuild a clean release APK once I flip it to `false` — I'll need this once the
>    device is confirmed working and I want the debug panel gone for good.

## Step 1b — Test on your laptop first, before touching the TV

The prompt above ends by asking Claude to hand you exact `flutter run` instructions
for an emulator (ideally an Android TV emulator via Android Studio's AVD Manager) or
a connected phone. Use that loop to shake out build/logic/Firestore-connection bugs
fast — it's much quicker than the build → sideload → walk-over-and-look cycle on the
real device. It can't tell you whether the original WebAssembly theory was right,
only the real TV can answer that, but it can confirm everything else about the app
is actually working before you ever touch physical hardware.

## Step 2 — Manual work (nothing here can be automated by Claude)

**2a. Register an Android app in Firebase console (~2 min)**
- Firebase console → `why-not-cafe-prod` project → ⚙️ Project settings → Add app →
  Android.
- Package name: anything you like, e.g. `com.whynotcafe.kitchendisplay` (must match
  whatever the new Claude session sets as `applicationId` in
  `android/app/build.gradle` — tell it this package name too).
- Skip the `google-services.json` download — the prompt has Claude use explicit
  `FirebaseOptions` instead. But after registering, click through to view the app's
  config values (Firebase shows these even without downloading the file) and copy
  **both** the **App ID** (format `1:871637263829:android:xxxxxxxx`) **and the
  Android app's own API key** — paste both over their placeholders in the new
  project. Do not reuse the web app's API key (see the "IMPORTANT" note in the
  prompt above) — if the API key silently doesn't work once you sideload the app
  (Firestore calls fail/hang with a permission or "API key not valid" style error),
  this is the first thing to double check.

**2b. Build the APK**
- The new Claude session will give the exact command, but it'll be
  `flutter build apk --release`, output at
  `build/app/outputs/flutter-apk/app-release.apk`.

**2c. Get the APK onto the Android TV** (no Play Store needed)
- Easiest: install the **Downloader** app (by AFTVnews) from the TV's app store if it
  has one — it can pull the APK straight from a URL. You could even upload the APK to
  the existing Firebase Hosting as a plain static file and point Downloader at that
  URL.
- Alternative: enable Developer Options on the TV (Settings → About → tap Build 7×),
  turn on Network debugging/ADB, then from a computer on the same network:
  `adb connect <tv-ip>:5555` then `adb install app-release.apk`.
- Either way, allow "Install unknown apps" for whichever app does the install.

**2d. Make it the thing that's always on screen**
- If the kiosk browser app is Fully Kiosk Browser (Pro tier), it has an **"App
  Mode"** that launches a chosen installed app instead of a URL, with auto-restart on
  crash — check if the license/version has it; if so, point it at this new app
  instead of the website URL, keeping the existing kiosk lockdown.
- Otherwise, Android's built-in **Screen Pinning** (Settings → Security → Screen
  pinning) locks the TV to this one app with no extra software.
- The prompt also has Claude add a boot-time auto-relaunch, so it recovers on its own
  after a power cut regardless of which lock-down method is used.

## Step 3 — After installing: closing the loop

- Launch the app on the TV and just look at it. With `kDebugOverlay = true`, any
  init/stream/parse error will be visible directly on screen — photograph or
  screen-record it and send it back to me (or paste the text if it's readable) and
  I'll diagnose from there.
- If the screen shows nothing at all (not even the debug panel) — that's the one
  failure mode the overlay can't catch (see the prompt's note on this). In that case
  the next step is `adb logcat` from a computer connected to the same network/USB,
  which is a manual step I'd walk you through separately if it comes to that.
- Once it's confirmed working end-to-end for a day or two, come back and I'll give
  you the follow-up prompt to flip `kDebugOverlay` to `false` and rebuild a clean
  release APK to reinstall.
