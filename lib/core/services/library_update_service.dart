import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../database/models/manga.dart';
import '../database/models/chapter.dart';
import '../parser/parser_registry.dart';
import '../notifications/notification_service.dart';

class LibraryUpdateService {
  static final LibraryUpdateService instance = LibraryUpdateService._internal();
  LibraryUpdateService._internal();

  @visibleForTesting
  LibraryUpdateService.forTesting({
    required AppDatabase database,
    Future<List<MangaChapter>> Function(Manga)? fetch,
    required Future<void> Function(Manga, List<MangaChapter>) notify,
    Duration Function()? elapsed,
  }) {
    _elapsedOverride = elapsed;
    _database = database;
    _fetchOverride = fetch;
    _notifyOverride = notify;
  }

  Duration Function()? _elapsedOverride;
  AppDatabase? _database;
  Future<List<MangaChapter>> Function(Manga)? _fetchOverride;
  Future<void> Function(Manga, List<MangaChapter>)? _notifyOverride;
  AppDatabase get _db => _database ?? AppDatabase.instance;
  final ValueNotifier<bool> isCheckingUpdates = ValueNotifier(false);
  final ValueNotifier<int> unseenUpdateCount = ValueNotifier(0);
  Timer? _startupTimer;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await NotificationService.instance.init();
    await refreshUnseenCount();
    _initialized = true;
    _startupTimer = Timer(const Duration(seconds: 4), () async {
      try {
        await checkForUpdates();
      } catch (error, stack) {
        debugPrint('Startup chapter check failed: $error\n$stack');
      }
    });
  }

  Future<void> refreshUnseenCount() async {
    unseenUpdateCount.value = await _db.getUnseenUpdateCount();
  }

  void dispose() => _startupTimer?.cancel();

  Future<int> checkForUpdates({bool silent = false, Duration? budget}) async {
    if (isCheckingUpdates.value) {
      throw StateError('Chapter check already running');
    }
    isCheckingUpdates.value = true;
    final watch = Stopwatch()..start();
    Duration elapsed() => _elapsedOverride?.call() ?? watch.elapsed;
    bool hasBudget() => budget == null || elapsed() < budget;
    int total = 0;
    final failures = <Object>[];
    try {
      final favorites = await _db.getFavorites();
      // Continue after the last attempted title on the next OS time slice.
      final cursor = await _db.getLibraryUpdateCursor();
      final previous = favorites.indexWhere((manga) => manga.id == cursor);
      final ordered = previous < 0
          ? favorites
          : [...favorites.skip(previous + 1), ...favorites.take(previous + 1)];
      for (final manga in ordered) {
        final remaining = budget == null ? null : budget - elapsed();
        if (remaining != null && remaining <= const Duration(seconds: 2)) {
          failures.add(TimeoutException('Chapter check budget exhausted'));
          break;
        }
        try {
          final parser = ParserRegistry.instance.getParser(manga.sourceId);
          if (_fetchOverride == null && parser == null) {
            throw StateError('Missing source ${manga.sourceId}');
          }
          final timeout = remaining == null
              ? const Duration(seconds: 10)
              : remaining - const Duration(seconds: 2);
          final remote =
              await (_fetchOverride?.call(manga) ??
                      parser!.getChaptersForUpdates(manga))
                  .timeout(
                    timeout < const Duration(seconds: 10)
                        ? timeout
                        : const Duration(seconds: 10),
                  );
          // A timed-out network Future cannot later write to the database.
          await _db.recordChapterUpdates(
            manga,
            remote,
            shouldContinue: hasBudget,
            onBatchCommitted: (added) async {
              total += added.length;
              if (!hasBudget()) {
                throw TimeoutException('Chapter check budget exhausted');
              }
              if (!silent && added.isNotEmpty) {
                added.sort((a, b) => b.number.compareTo(a.number));
                if (_notifyOverride != null) {
                  await _notifyOverride!(manga, added);
                } else {
                  await NotificationService.instance
                      .showChapterUpdateNotification(
                        id: notificationId(manga.id),
                        mangaTitle: manga.title,
                        chapterTitle: added.first.title,
                        newCount: added.length,
                        payload: manga.id,
                      );
                }
              }
              if (!hasBudget()) {
                throw TimeoutException('Chapter check budget exhausted');
              }
            },
          );
        } catch (error, stack) {
          failures.add(error);
          debugPrint('Chapter check failed for ${manga.id}: $error\n$stack');
        } finally {
          await _db.setLibraryUpdateCursor(manga.id);
        }
      }
      await refreshUnseenCount();
      if (failures.isNotEmpty) {
        throw StateError(
          '${failures.length} chapter checks failed: ${failures.first}',
        );
      }
      return total;
    } finally {
      isCheckingUpdates.value = false;
    }
  }

  // Stable across engine/process restarts, unlike String.hashCode.
  static int notificationId(String value) => value.codeUnits.fold<int>(
    0,
    (hash, unit) => (hash * 31 + unit) & 0x7fffffff,
  );
}
