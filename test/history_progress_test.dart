import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panovault/core/database/app_database.dart';
import 'package:panovault/core/database/models/history_entry.dart';
import 'package:panovault/features/history/providers/history_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Only delays History's first read; all other reads use the real SQLite DB.
class DelayedHistoryDatabase extends AppDatabase {
  DelayedHistoryDatabase(super.database) : super.withDatabase();

  Completer<List<HistoryEntry>>? nextHistory;

  @override
  Future<List<HistoryEntry>> getHistory() async =>
      nextHistory == null ? [] : nextHistory!.future;
}

void main() {
  late Database sqlite;
  late AppDatabase database;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    sqlite = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    database = AppDatabase.withDatabase(sqlite);
    await sqlite.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY, manga_id TEXT NOT NULL, number REAL NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        last_read_page INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await sqlite.execute(
      'CREATE INDEX idx_chapters_manga ON chapters(manga_id)',
    );
  });
  tearDown(() => sqlite.close());

  Future<void> chapters(
    String id,
    List<double> numbers, {
    double? read,
    double? started,
  }) async {
    for (final number in numbers) {
      await sqlite.insert('chapters', {
        'id': '$id/$number',
        'manga_id': id,
        'number': number,
        'is_read': number == read ? 1 : 0,
        'last_read_page': number == started ? 2 : 0,
      });
    }
  }

  test(
    'infers earlier chapters without writing or completing started chapter',
    () async {
      await chapters('source_book', [0, 1, 1.5, 2, 3, 4], started: 2);
      final before = await sqlite.query('chapters', orderBy: 'id');
      await sqlite.execute('PRAGMA query_only = ON');
      final progress = await database.getReadingProgressForManga([
        'source_book',
      ]);
      expect(progress['source_book'], 3 / 6);
      expect(progress['book'], 3 / 6);
      expect(await sqlite.query('chapters', orderBy: 'id'), before);
      expect(
        await database.getReadingProgressForManga(['source_book']),
        progress,
      );
    },
  );

  test(
    'completed highest chapter counts itself and all strictly earlier rows',
    () async {
      await chapters('book', [-1, 0, 1, 2, 2.5, 3], read: 2.5, started: 1);
      expect(
        (await database.getReadingProgressForManga(['book']))['book'],
        5 / 6,
      );
    },
  );

  test(
    'untouched negative and zero chapter numbers are not inferred read',
    () async {
      await chapters('book', [-1, 0, 1]);
      expect(await database.getReadingProgressForManga(['book']), {
        'book': 0.0,
      });
    },
  );

  test('empty and missing ids have no progress entries', () async {
    expect(await database.getReadingProgressForManga([]), isEmpty);
    expect(await database.getReadingProgressForManga(['missing']), isEmpty);
  });

  test('raw stored ids satisfy requested prefixed aliases', () async {
    await chapters('book', [1, 2, 3], read: 2);
    expect(await database.getReadingProgressForManga(['source_book']), {
      'book': 2 / 3,
      'source_book': 2 / 3,
    });
  });

  test(
    'exact source progress wins over raw fallback independent of request order',
    () async {
      await chapters('book', [1, 2, 3, 4], read: 1);
      await chapters('a_book', [1, 2, 3, 4], read: 2);
      await chapters('b_book', [1, 2, 3, 4], read: 4);
      for (final ids in [
        ['a_book', 'b_book', 'book'],
        ['book', 'b_book', 'a_book'],
      ]) {
        final result = await database.getReadingProgressForManga(ids);
        expect(result['a_book'], 0.5);
        expect(result['b_book'], 1.0);
        expect(result['book'], 0.25);
      }
    },
  );

  test('other sources and substring/wildcard ids cannot infer reads', () async {
    await chapters('a_book', [1, 2, 3]);
    await chapters('b_book', [1, 2, 3], read: 3);
    await chapters('prefix_a_book_suffix', [1, 2, 3], read: 3);
    await chapters('a_b%ok', [1, 2, 3]);
    await chapters('a_bXok', [1, 2, 3], read: 3);
    final result = await database.getReadingProgressForManga([
      'a_book',
      'a_b%ok',
    ]);
    expect(result['a_book'], 0.0);
    expect(result['a_b%ok'], 0.0);
    expect(result, isNot(contains('b_book')));
    final aliases = await database.getReadingProgressForManga([
      'b_book',
      'c_book',
    ]);
    expect(aliases['b_book'], 1.0);
    expect(aliases, isNot(contains('c_book')));
  });

  test(
    'refresh retains data and counts until the next SQLite load finishes',
    () async {
      await sqlite.execute('''
      CREATE TABLE manga (id TEXT PRIMARY KEY, title TEXT,
        url TEXT, cover_url TEXT, source_id TEXT, is_favorite INTEGER)
    ''');
      await sqlite.execute('''
      CREATE TABLE chapter_updates (id TEXT, manga_id TEXT, manga_title TEXT,
        cover_url TEXT, source_id TEXT, chapter_id TEXT, chapter_title TEXT,
        chapter_number REAL, detected_at TEXT, is_seen INTEGER)
    ''');
      await sqlite.insert('manga', {
        'id': 'a_book',
        'title': 'Book',
        'url': '',
        'cover_url': '',
        'source_id': 'a',
        'is_favorite': 1,
      });
      for (var i = 1; i <= 2; i++) {
        await sqlite.insert('chapter_updates', {
          'id': 'update$i',
          'manga_id': 'a_book',
          'manga_title': 'Book',
          'cover_url': '',
          'source_id': 'a',
          'chapter_id': 'chapter$i',
          'chapter_title': 'Chapter $i',
          'chapter_number': i,
          'detected_at': '2026-01-0$i',
          'is_seen': i == 1 ? 0 : 1,
        });
      }
      await chapters('a_book', [1, 2, 3], read: 2);
      final delayed = DelayedHistoryDatabase(sqlite);
      final notifier = HistoryNotifier(database: delayed);
      final container = ProviderContainer(
        overrides: [historyProvider.overrideWith((ref) => notifier)],
      );
      addTearDown(container.dispose);
      final loaded = Completer<void>();
      final subscription = container.listen(historyProvider, (_, next) {
        if (!next.isLoading && next.hasValue && !loaded.isCompleted) {
          loaded.complete();
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);
      await loaded.future;
      final previous = container.read(historyProvider).requireValue;
      expect(previous.allItems.length, 2);
      expect(previous.updateCount, 2);
      expect(previous.unseenUpdateCount, 1);
      expect(previous.favoriteMangaIds, {'a_book'});
      expect(previous.updateCards.single.updateCount, 2);
      expect(previous.updateCards.single.readingProgress, 2 / 3);
      expect(previous.updateCards.single.isFavorite, isTrue);
      delayed.nextHistory = Completer<List<HistoryEntry>>();
      final refreshing = notifier.loadHistory();
      final state = container.read(historyProvider);
      expect(state.isLoading, isFalse);
      expect(state.hasValue, isTrue);
      expect(state.requireValue, same(previous));
      expect(
        state.when(
          data: (_) => 'data',
          loading: () => 'loading',
          error: (_, _) => 'error',
        ),
        'data',
      );
      delayed.nextHistory!.complete([]);
      await refreshing;
      final next = container.read(historyProvider);
      expect(next.isLoading, isFalse);
      expect(next.requireValue.readCount, previous.readCount);
      expect(next.requireValue.updateCount, previous.updateCount);

      delayed.nextHistory = Completer<List<HistoryEntry>>();
      final failedRefresh = notifier.loadHistory();
      final refreshError = StateError('SQLite read failed');
      final refreshStackTrace = StackTrace.current;
      delayed.nextHistory!.completeError(refreshError, refreshStackTrace);
      await failedRefresh;
      final failed = container.read(historyProvider);
      expect(failed.hasError, isFalse);
      expect(notifier.lastRefreshError, same(refreshError));
      expect(notifier.lastRefreshStackTrace, same(refreshStackTrace));
      expect(failed.requireValue, same(next.requireValue));
      expect(
        failed.when(
          data: (_) => 'data',
          loading: () => 'loading',
          error: (_, _) => 'error',
        ),
        'data',
      );
      delayed.nextHistory = Completer<List<HistoryEntry>>();
      final recovery = notifier.loadHistory();
      expect(notifier.lastRefreshError, same(refreshError));
      expect(
        container.read(historyProvider).requireValue,
        same(next.requireValue),
      );
      await sqlite.delete('chapter_updates');
      delayed.nextHistory!.complete([]);
      await recovery;
      expect(notifier.lastRefreshError, isNull);
      expect(notifier.lastRefreshStackTrace, isNull);
      final recovered = container.read(historyProvider).requireValue;
      expect(recovered.allItems, isEmpty);
      expect(recovered.updateCards, isEmpty);
      expect(recovered.updateCount, 0);
    },
  );

  test('first-load failure remains visible through the error branch', () async {
    final delayed = DelayedHistoryDatabase(sqlite)
      ..nextHistory = Completer<List<HistoryEntry>>();
    final notifier = HistoryNotifier(database: delayed);
    final container = ProviderContainer(
      overrides: [historyProvider.overrideWith((ref) => notifier)],
    );
    addTearDown(container.dispose);
    expect(container.read(historyProvider).isLoading, isTrue);
    final failed = Completer<AsyncValue<UnifiedHistoryData>>();
    final subscription = container.listen(historyProvider, (_, next) {
      if (next.hasError && !failed.isCompleted) failed.complete(next);
    });
    addTearDown(subscription.close);
    final error = StateError('Initial SQLite read failed');
    delayed.nextHistory!.completeError(error);
    final state = await failed.future;
    expect(state.hasValue, isFalse);
    expect(state.error, same(error));
    expect(
      state.when(
        data: (_) => 'data',
        loading: () => 'loading',
        error: (_, _) => 'error',
      ),
      'error',
    );
    expect(notifier.lastRefreshError, isNull);
  });
}
