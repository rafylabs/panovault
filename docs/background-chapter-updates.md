# Background chapter updates

## Implementation

Android uses OS WorkManager through `workmanager`; iOS uses BGTaskScheduler / BGAppRefreshTask, not a Dart periodic timer. Task identifier: `com.panovault.library.chapter_updates`. The requested interval and initial delay are 30 minutes, **not a timing guarantee**. Android periodic work uses `ExistingPeriodicWorkPolicy.keep` and a connected-network constraint. The iOS refresh API does not enforce Dart's network constraint; offline source requests fail normally and the task reports failure. iOS ultimately decides whether/when another refresh runs.

The VM entry point initializes Flutter/plugin registration, reloads custom preferences and database-backed sources, and initializes local notifications without requesting permission. Foreground startup and Settings retain explicit permission requests. AppDelegate registers background plugins and the task launch handler before completing startup, retaining Flutter's implicit-engine registration callback. Deployment target is already iOS 15.0; no target bump is needed. Info.plist enables `fetch` and permits the exact task identifier. Android uses the plugin's merged WorkManager manifest; this feature needs no foreground service or exact-alarm permission.

The same chapter-check service serves headless, startup (one delayed check), and manual actions. Headless initialization has a five-second timeout and its check has a 20-second cooperative budget. Startup/manual checks have no overall budget and traverse the full library; all paths allow at most ten seconds per source request. The last attempted title is persisted to resume fairly on a later OS slice, including when that title's catalog is only partially stored. Timed-out fetch futures cannot later insert chapters or notify. Budget checkpoints run before each persistence batch and before/after notification posting. Already-started database/plugin I/O, cursor writes and final badge reads are awaited, not timed out or forcibly cancelled; they can overrun the target. This is not a hard deadline. OS expiration may terminate the engine independently.

Remote requests happen outside SQLite transactions. Each transaction handles at most 100 unique catalog entries in ascending chapter-number/ID order, atomically storing inserted chapters, update logs, and a per-title last-ID checkpoint with the original baseline/maximum threshold. Later checks refetch the catalog and resume after that ID (restart if it vanished); source reordering does not change traversal order. Full response parsing, de-duplication and sorting still happen in memory, so this is a persistence work bound, not a response-size/memory bound. Source IDs/numbering must remain stable: renumbering or inserting entries before a saved marker can defer/omit those entries in that pass. Transactions never replace read progress; an interrupted first-fetch baseline stays quiet on continuation, and older backfills do not notify. Notifications are best-effort per committed batch (up to 100 candidates); the stable title ID replaces earlier batch alerts, and its count represents that batch, not the entire check. The same transaction decides which caller owns the notification candidates, reducing foreground/headless duplicate alerts. A two-second SQLite busy timeout and per-isolate pending-open future reduce lock/open races. Concurrent-client tests share an FFI connection: actual separate mobile engines/processes still require device validation.

Chapter-update jobs use explicit strict chapter APIs for every registered production parser: MangaPill, WeebCentral, Shinigami, and database-backed DynamicMangaParser. Request/parsing errors and malformed entries propagate instead of returning empty/partial success. Shinigami validates list/entry/pagination shapes (including boolean `meta.has_next`), missing/repeated cursors, contradictory empty continuation pages, and the 40-page safety limit; an unfinished traversal fails rather than persisting its partial catalog. Existing reader callers keep their legacy behavior, including WeebCentral's empty fallback and Shinigami's partial fallback. The base update API fails closed with UnsupportedError rather than calling the legacy reader method; the unregistered legacy Komiku parser is therefore not silently enabled for updates. Future parser registrations must explicitly implement strict fetching. Valid empty REST lists with valid pagination metadata, and nonblank HTML pages with no matching chapter elements, remain empty catalogs. Blank/missing built-in HTML responses fail; HTML selector drift or an error/challenge page that merely produces no matches cannot be distinguished from a genuine empty HTML catalog.

New chapter counts update the in-app badge; resume rereads the database because background isolates do not share ValueNotifiers. Errors are logged; dispatch returns false on initialization/source/check failures. Android interprets failure according to WorkManager retry policy; iOS remains OS-scheduled. Manual actions display an error instead of claiming no new chapters when some sources fail, while preserving successfully stored updates.

## Limits

- Android Doze, battery optimization, OEM task killers, connectivity, and user force-stop can defer/prevent work. There is no permanent background service. Reopen after force-stop.
- iOS needs Background App Refresh enabled and may run far less frequently than requested. User force-quit prevents background launch until reopened. Low Power Mode/system policy may suppress refresh.
- Notifications require foreground permission approval and enabled app/channel settings. Successful plugin posting does not prove that the user saw a notification.
- Local notification posting is best effort, not an atomic database/OS operation. If the engine is killed after storing an update but before posting, or notification posting fails, the update remains in the Updates list/badge but there is no durable notification-outbox replay. Stable per-title notification IDs replace rather than stack alerts for that title.
- First fetch for a title with no locally stored chapters establishes a baseline without alerting about its entire catalog. Future new chapters alert normally.

## Versions and official references

Verified with Flutter **3.50.1**, Dart **3.14.0**. Resolved lockfile versions: `workmanager 0.10.10`, `workmanager_android 0.10.9`, `workmanager_apple 0.9.11`. Dependency declaration: `workmanager: ^0.10.10`.

- Package/version/API: https://pub.dev/packages/workmanager/versions/0.10.10
- Dart API reference: https://pub.dev/documentation/workmanager/0.10.10/workmanager/Workmanager-class.html
- Official setup / iOS periodic refresh option: https://docs.page/fluttercommunity/flutter_workmanager/quickstart
- Official project README: https://github.com/fluttercommunity/flutter_workmanager/blob/main/workmanager/README.md
- Apple implementation for the resolved version: https://pub.dev/packages/workmanager_apple/versions/0.9.11
- Android implementation for the resolved version: https://pub.dev/packages/workmanager_android/versions/0.10.9

In addition to the quickstart, the resolved package sources were checked for `registerPeriodicTask(withIdentifier:earliestBeginInSeconds:)`, `registerLaunchHandlers()`, `setPluginRegistrantCallback`, and Dart `initialize` / `registerPeriodicTask` / `ExistingPeriodicWorkPolicy.keep`. This matters because older README examples omit newer launch registration and implicit-engine embedding differs from older Flutter templates.

## Verification and remaining device checks

Run using the project SDK, not the older default SDK:

```sh
/opt/data/toolchains/flutter-3.50.1/bin/flutter analyze
/opt/data/toolchains/flutter-3.50.1/bin/flutter test
git diff --check
```

Full test suite: **145 tests passed**; `flutter analyze` reports **No issues found**, and `git diff --check` passes. Parser regressions use production Dio client interceptors for built-in failures/valid empties, malformed entries and Shinigami pagination failures, plus SQLite-backed dispatcher/service checks that failed catalogs cannot persist new chapters or notify. Mixed valid/malformed catalogs cover dynamic HTML missing/empty/blank links, dynamic REST blank/unsupported/nonfinite IDs and missing/invalid/nonfinite chapter numbers, and MangaPill links without a chapter-specific route. These checks assert unchanged chapter rows/read progress, no update rows or catalog checkpoints, no notifications, scheduler failure, and continued permissive reader fetching. Dynamic valid-empty HTML/REST catalogs and legitimate string/numeric IDs with finite configured chapter numbers are also covered. Static validation parses Info.plist and Android manifest XML, checks matching Dart/native/permitted task identifiers, implicit-engine/plugin/launch registration, required Android permissions, and iOS deployment targets (15.0). These static checks do **not** compile Swift/Kotlin or prove manifest merging.

This host has no Android SDK, Java, adb, or xcodebuild. No toolchains were installed. **Android/iOS native builds, physical-device scheduling, permission prompts, notification delivery and lifecycle tests remain unverified.**

On provisioned native build hosts/devices:

1. Build Android APK and an iOS device app; resolve CocoaPods and inspect the merged Android manifest/plugin registration.
2. Favorite a source/title; establish a baseline; grant notification permission in foreground. Background the app, make a real new chapter available, and confirm the OS-triggered callback, one update record and one local alert. Verify notification initialization never prompts headlessly.
3. On iOS use Xcode/LLDB BGTaskScheduler launch simulation with the exact identifier for callback testing, then test actual OS-driven scheduling separately (simulation does not prove cadence).
4. Repeat with a custom JSON source and database-backed dynamic source, offline/reconnected network, denied notification permission, disabled Background App Refresh, battery/Doze conditions, and app restart/reboot where supported.
5. Race manual refresh and OS callbacks; verify chapter read position survives and no duplicate update records/alerts appear. Resume foreground and verify the badge reflects headless writes.
6. Test force-stop/force-quit and reopening; do not expect background execution while explicitly stopped. Test many favorites and a slow/failing first source to verify persisted cursor progress.
