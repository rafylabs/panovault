import 'dart:async';

import 'package:dio/dio.dart';
import 'package:panovault/core/network/http_client.dart';
import 'package:panovault/core/parser/dynamic_manga_parser.dart';
import 'package:panovault/core/parser/parser_registry.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:panovault/core/database/app_database.dart';
import 'package:panovault/core/database/models/chapter.dart';
import 'package:panovault/core/database/models/manga.dart';
import 'package:panovault/core/services/background_library_updates.dart';
import 'package:panovault/core/services/library_update_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const manga = Manga(
  id: 'm',
  title: 'Test',
  url: 'https://example.com/m',
  coverUrl: '',
  sourceId: 'test',
  isFavorite: true,
);
MangaChapter chapter(int n) => MangaChapter(
  id: 'c$n',
  mangaId: 'm',
  title: 'Chapter $n',
  number: n.toDouble(),
  url: 'https://example.com/$n',
);

class _RecordingScheduler implements Workmanager {
  final calls = <Invocation>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database raw;
  late AppDatabase db;
  setUp(() async {
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await raw.execute(
      'CREATE TABLE manga (id TEXT PRIMARY KEY, title TEXT, '
      'url TEXT, cover_url TEXT, source_id TEXT, is_favorite INTEGER, '
      'alt_title TEXT, author TEXT, artist TEXT, description TEXT, status TEXT, '
      'rating REAL, genres TEXT, last_read_at TEXT)',
    );
    await raw.execute(
      'CREATE TABLE chapters (id TEXT PRIMARY KEY, manga_id TEXT, '
      'title TEXT, number REAL, url TEXT, scanlator TEXT, upload_date TEXT, '
      'is_read INTEGER, last_read_page INTEGER, last_read_offset REAL, page_count INTEGER)',
    );
    await raw.execute(
      'CREATE TABLE chapter_updates (id TEXT PRIMARY KEY, manga_id TEXT, '
      'manga_title TEXT, cover_url TEXT, source_id TEXT, chapter_id TEXT, chapter_title TEXT, '
      'chapter_number REAL, detected_at TEXT, is_seen INTEGER)',
    );
    await raw.execute(
      'CREATE TABLE library_update_state (id INTEGER PRIMARY KEY, cursor TEXT)',
    );
    await raw.execute(
      'CREATE TABLE library_update_catalog '
      '(manga_id TEXT PRIMARY KEY, baseline INTEGER NOT NULL, maximum REAL NOT NULL, last_id TEXT)',
    );
    await raw.insert('manga', manga.toMap());
    db = AppDatabase.withDatabase(raw);
  });
  tearDown(() => raw.close());

  for (final failure in [
    'network',
    'json',
    'shape',
    'entry',
    'missing-id',
    'selector',
    'empty',
  ]) {
    test(
      'production dynamic parser reports $failure failure to dispatcher',
      () async {
        final parser = DynamicMangaParser(
          CustomSourceConfig(
            id: 'test',
            name: 'Test',
            domain: 'example.com',
            type: failure == 'selector' ? 'html' : 'rest',
            customSelectors: {
              'api': {
                'chaptersEndpoint': 'https://example.com/api',
                'chaptersPath': 'data',
              },
              'selectors': {'chapters': '['},
            },
          ),
        );
        ParserRegistry.instance.registerParser(parser);
        final interceptor = InterceptorsWrapper(
          onRequest: (options, handler) {
            if (failure == 'network') {
              handler.reject(
                DioException(requestOptions: options, error: 'offline'),
              );
            } else {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: failure == 'json'
                      ? '{bad'
                      : failure == 'shape'
                      ? {'data': 'wrong'}
                      : failure == 'entry'
                      ? {
                          'data': [42],
                        }
                      : failure == 'missing-id'
                      ? {'data': [{'title': 'No ID'}]}
                      : failure == 'empty'
                      ? {'data': []}
                      : '<html></html>',
                ),
              );
            }
          },
        );
        PanovaultHttpClient.instance.dio.interceptors.insert(0, interceptor);
        addTearDown(() {
          PanovaultHttpClient.instance.dio.interceptors.remove(interceptor);
          ParserRegistry.instance.resetForTesting();
        });
        final service = LibraryUpdateService.forTesting(
          database: db,
          notify: (_, _) async => fail('failure must not notify'),
        );
        expect(
          await dispatchLibraryUpdate(
            libraryUpdateTask,
            initialize: () async {},
            check: () async {
              await service.checkForUpdates();
            },
          ),
          failure == 'empty',
        );
        expect(await db.getChapters('m'), isEmpty);
        expect(await db.getUnseenUpdateCount(), 0);
        // Reader callers retain the legacy best-effort fallback.
        expect(await parser.getChapters(manga), isEmpty);
      },
    );
  }

  for (final source in ['mangapill', 'weebcentral', 'shinigami']) {
    test('$source HTTP failure cannot persist chapters or notify in update job', () async {
      final registered = ParserRegistry.instance.getParser(source)!;
      await raw.update('manga', {'source_id': source}, where: 'id = ?', whereArgs: ['m']);
      await raw.insert('chapters', chapter(1).copyWith(isRead: true, lastReadPage: 7).toMap());
      final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
        // Shinigami fails only after successfully parsing a new chapter on page one.
        if (source == 'shinigami' && options.uri.queryParameters['cursor'] == null) {
          handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: {
            'data': [{'chapter_id': 'new', 'chapter_number': 2}],
            'meta': {'has_next': true, 'next_cursor': 'page-two'},
          }));
        } else {
          handler.reject(DioException(requestOptions: options, error: 'offline'));
        }
      });
      PanovaultHttpClient.instance.dio.interceptors.insert(0, interceptor);
      addTearDown(() => PanovaultHttpClient.instance.dio.interceptors.remove(interceptor));
      expect(registered.id, source);
      final service = LibraryUpdateService.forTesting(
        database: db,
        notify: (_, _) async => fail('failed catalog must not notify'),
      );
      expect(await dispatchLibraryUpdate(libraryUpdateTask,
        initialize: () async {}, check: () async { await service.checkForUpdates(); }), false);
      final saved = await db.getChapters('m');
      expect(saved, hasLength(1));
      expect(saved.single.id, 'c1');
      expect(saved.single.isRead, true);
      expect(saved.single.lastReadPage, 7);
      expect(await db.getUnseenUpdateCount(), 0);
    });
  }

  final malformedCatalogs = <({String name, String source, Object data})>[
    for (final href in [null, '', '   '])
      (
        name: 'dynamic HTML href $href',
        source: 'html',
        data: '<div id="chapters"><a href="/chapters/new">Chapter 2</a>'
            '<a${href == null ? '' : ' href="$href"'}>Chapter 1</a></div>',
      ),
    for (final id in [null, '', '   ', true, <String, Object>{}, <Object>[], double.nan, double.infinity])
      (
        name: 'dynamic REST ID $id',
        source: 'rest',
        data: {
          'data': [
            {'id': 'new', 'chapter_number': 2},
            {'id': id, 'chapter_number': 1},
          ],
        },
      ),
    for (final number in [null, '', 'bad', true, <Object>[], <String, Object>{}, 'NaN', 'Infinity', '-Infinity', double.nan, double.infinity])
      (
        name: 'dynamic REST number $number',
        source: 'rest',
        data: {
          'data': [
            {'id': 'new', 'chapter_number': 2},
            {'id': 'bad', 'chapter_number': number},
          ],
        },
      ),
    for (final href in ['/chapters/', '/chapters', '/manga/not-a-chapter'])
      (
        name: 'MangaPill route $href',
        source: 'mangapill',
        data: '<div id="chapters"><a href="/chapters/new">Chapter 2</a>'
            '<a href="$href">Chapter 1</a></div>',
      ),
  ];
  for (final fixture in malformedCatalogs) {
    test('${fixture.name} rejects whole production catalog without DB/notify effects', () async {
      final source = fixture.source == 'mangapill' ? 'mangapill' : 'test';
      final parser = fixture.source == 'mangapill'
          ? ParserRegistry.instance.getParser(source)!
          : DynamicMangaParser(CustomSourceConfig(
              id: source,
              name: 'Test',
              domain: 'example.com',
              type: fixture.source,
              customSelectors: {
                'api': {'chaptersEndpoint': 'https://example.com/api'},
                'selectors': {'chapters': 'div#chapters a'},
              },
            ));
      ParserRegistry.instance.registerParser(parser);
      await raw.update('manga', {'source_id': source}, where: 'id = ?', whereArgs: ['m']);
      await raw.insert('chapters', chapter(1).copyWith(isRead: true, lastReadPage: 7).toMap());
      final before = await raw.query('chapters');
      var requests = 0;
      final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
        requests++;
        handler.resolve(Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: fixture.data,
        ));
      });
      PanovaultHttpClient.instance.dio.interceptors.insert(0, interceptor);
      addTearDown(() {
        PanovaultHttpClient.instance.dio.interceptors.remove(interceptor);
        ParserRegistry.instance.resetForTesting();
      });
      await expectLater(parser.getChaptersForUpdates(manga), throwsFormatException);
      var notifications = 0;
      final service = LibraryUpdateService.forTesting(
        database: db,
        notify: (_, _) async { notifications++; },
      );
      expect(await dispatchLibraryUpdate(libraryUpdateTask,
        initialize: () async {}, check: () async { await service.checkForUpdates(); }), false);
      expect(requests, 2);
      expect(await raw.query('chapters'), before);
      expect(await raw.query('chapter_updates'), isEmpty);
      expect(await raw.query('library_update_catalog'), isEmpty);
      expect(notifications, 0);
      // Strictness is update-only; the legacy reader must still complete.
      final reader = await parser.getChapters(manga);
      expect(reader, isNotEmpty);
    });
  }

  for (final type in ['rest', 'html']) {
    test('dynamic $type accepts valid empty production catalog', () async {
      final parser = DynamicMangaParser(CustomSourceConfig(
        id: 'test', name: 'Test', domain: 'example.com', type: type,
        customSelectors: {
          'api': {'chaptersEndpoint': 'https://example.com/api'},
          'selectors': {'chapters': 'div#chapters a'},
        },
      ));
      ParserRegistry.instance.registerParser(parser);
      final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200,
          data: type == 'rest' ? {'data': []} : '<div id="chapters"></div>'));
      });
      PanovaultHttpClient.instance.dio.interceptors.insert(0, interceptor);
      addTearDown(() {
        PanovaultHttpClient.instance.dio.interceptors.remove(interceptor);
        ParserRegistry.instance.resetForTesting();
      });
      expect(await parser.getChaptersForUpdates(manga), isEmpty);
      expect(await parser.getChapters(manga), isEmpty);
      final service = LibraryUpdateService.forTesting(database: db,
        notify: (_, _) async => fail('empty catalog must not notify'));
      expect(await service.checkForUpdates(), 0);
      expect(await raw.query('chapters'), isEmpty);
      expect(await raw.query('chapter_updates'), isEmpty);
    });
  }

  test('dynamic REST accepts string and numeric IDs and finite configured numbers', () async {
    final parser = DynamicMangaParser(const CustomSourceConfig(
      id: 'test', name: 'Test', domain: 'example.com', type: 'rest',
      customSelectors: {'api': {
        'chaptersEndpoint': 'https://example.com/api',
        'chapterIdKey': 'key', 'chapterNumberKey': 'number',
      }},
    ));
    final interceptor = InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: {
        'data': [
          {'key': 'special', 'number': '2.5'},
          {'key': 42, 'number': 1},
          {'key': 0, 'number': 0},
        ],
      }));
    });
    PanovaultHttpClient.instance.dio.interceptors.insert(0, interceptor);
    addTearDown(() => PanovaultHttpClient.instance.dio.interceptors.remove(interceptor));
    final chapters = await parser.getChaptersForUpdates(manga);
    expect(chapters.map((c) => c.id), ['test_m_special', 'test_m_42', 'test_m_0']);
    expect(chapters.map((c) => c.number), [2.5, 1, 0]);
    expect((await parser.getChapters(manga)).map((c) => c.id), chapters.map((c) => c.id));
  });

  test('catalog persistence checkpoints between bounded batches and resumes quietly', () async {
    final remote = List.generate(251, (i) => chapter(i + 1));
    var checks = 0;
    await expectLater(
      db.recordChapterUpdates(
        manga,
        remote,
        shouldContinue: () => checks++ == 0,
      ),
      throwsStateError,
    );
    expect(await db.getChapters('m'), hasLength(100));
    expect(await db.getUnseenUpdateCount(), 0);
    // A new database client represents a later job; partial baseline stays quiet.
    expect(
      await AppDatabase.withDatabase(raw).recordChapterUpdates(manga, remote),
      isEmpty,
    );
    expect(await db.getChapters('m'), hasLength(251));
    expect(await db.getUnseenUpdateCount(), 0);
    expect(await db.recordChapterUpdates(manga, [chapter(252)]), hasLength(1));
  });

  test(
    'interrupted update keeps original threshold and read progress',
    () async {
      await raw.insert(
        'chapters',
        chapter(2).copyWith(isRead: true, lastReadPage: 5).toMap(),
      );
      final remote = List.generate(251, (i) => chapter(251 - i));
      var checks = 0;
      await expectLater(
        db.recordChapterUpdates(
          manga,
          remote,
          shouldContinue: () => checks++ == 0,
        ),
        throwsStateError,
      );
      expect(await db.getChapters('m'), hasLength(100));
      expect(await db.getUnseenUpdateCount(), 98);
      await AppDatabase.withDatabase(raw).recordChapterUpdates(manga, remote.reversed.toList());
      expect(await db.getUnseenUpdateCount(), 249);
      expect(await db.recordChapterUpdates(manga, remote), isEmpty);
      final saved = (await db.getChapters('m')).firstWhere((c) => c.id == 'c2');
      expect(saved.isRead, true);
      expect(saved.lastReadPage, 5);
    },
  );

  test('service stops after committed batch when budget expires and rotates titles', () async {
    await raw.insert('chapters', chapter(1).toMap());
    final second = manga.copyWith(id: 'second', title: 'Z second');
    await raw.insert('manga', second.toMap());
    var elapsed = Duration.zero;
    final fetched = <String>[];
    final notified = <String>[];
    final service = LibraryUpdateService.forTesting(
      database: db,
      elapsed: () => elapsed,
      fetch: (title) async {
        fetched.add(title.id);
        return title.id == 'm'
            ? List.generate(251, (i) => chapter(252 - i))
            : [];
      },
      notify: (title, added) async {
        notified.add(title.id);
        expect(added, hasLength(100));
        elapsed = const Duration(seconds: 20);
      },
    );
    await expectLater(
      service.checkForUpdates(budget: const Duration(seconds: 20)),
      throwsStateError,
    );
    expect(await db.getChapters('m'), hasLength(101));
    expect(await db.getLibraryUpdateCursor(), 'm');
    expect(fetched, ['m']);
    // Foreground has no overall budget, even after simulated elapsed time.
    expect(await service.checkForUpdates(silent: true), 151);
    expect(fetched, ['m', 'second', 'm']);
    expect(notified, ['m']);
    expect(await db.getChapters('m'), hasLength(252));
    expect(await db.getUnseenUpdateCount(), 251);
  });

  test(
    'mobile scheduling is unique, periodic and network constrained',
    () async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        final scheduler = _RecordingScheduler();
        await registerBackgroundLibraryUpdates(
          scheduler: scheduler,
          platform: platform,
        );
        expect(scheduler.calls.map((c) => c.memberName), [
          #initialize,
          #registerPeriodicTask,
        ]);
        final request = scheduler.calls.last;
        expect(request.positionalArguments, [
          libraryUpdateTask,
          libraryUpdateTask,
        ]);
        expect(request.namedArguments[#frequency], const Duration(minutes: 30));
        expect(
          request.namedArguments[#initialDelay],
          const Duration(minutes: 30),
        );
        expect(
          request.namedArguments[#existingWorkPolicy],
          ExistingPeriodicWorkPolicy.keep,
        );
        expect(
          (request.namedArguments[#constraints] as Constraints).networkType,
          NetworkType.connected,
        );
      }
      final desktop = _RecordingScheduler();
      await registerBackgroundLibraryUpdates(
        scheduler: desktop,
        platform: TargetPlatform.linux,
      );
      expect(desktop.calls, isEmpty);
    },
  );

  test(
    'dispatch initializes before checking and rejects unrelated tasks',
    () async {
      final calls = <String>[];
      expect(
        await dispatchLibraryUpdate(
          'unknown',
          initialize: () async => calls.add('init'),
          check: () async => calls.add('check'),
        ),
        false,
      );
      expect(calls, isEmpty);
      expect(
        await dispatchLibraryUpdate(
          libraryUpdateTask,
          initialize: () async => calls.add('init'),
          check: () async => calls.add('check'),
        ),
        true,
      );
      expect(calls, ['init', 'check']);
    },
  );
  test('initialization and check failures are reported to scheduler', () async {
    var checked = false;
    expect(
      await dispatchLibraryUpdate(
        libraryUpdateTask,
        initialize: () async => throw StateError('init'),
        check: () async {
          checked = true;
        },
      ),
      false,
    );
    expect(checked, false);
    expect(
      await dispatchLibraryUpdate(
        libraryUpdateTask,
        initialize: () async {},
        check: () async => throw StateError('network'),
      ),
      false,
    );
  });
  test(
    'first fetch establishes baseline without flooding old notifications',
    () async {
      expect(
        await db.recordChapterUpdates(manga, [chapter(1), chapter(2)]),
        isEmpty,
      );
      expect(await db.getChapters('m'), hasLength(2));
      expect(await db.getUnseenUpdateCount(), 0);
    },
  );
  test('new chapters logged once; duplicates, backfills and read progress preserved', () async {
    await raw.insert(
      'chapters',
      chapter(2).copyWith(isRead: true, lastReadPage: 5).toMap(),
    );
    final remote = [chapter(1), chapter(2), chapter(3), chapter(3), chapter(4)];
    expect(
      (await db.recordChapterUpdates(manga, remote)).map((c) => c.number),
      [4, 3],
    );
    expect(await db.recordChapterUpdates(manga, remote), isEmpty);
    expect(await db.getUnseenUpdateCount(), 2);
    final saved = (await db.getChapters('m')).firstWhere((c) => c.id == 'c2');
    expect(saved.isRead, true);
    expect(saved.lastReadPage, 5);
  });
  test('concurrent service clients do not duplicate chapter logs', () async {
    await raw.insert('chapters', chapter(1).toMap());
    final other = AppDatabase.withDatabase(raw);
    final results = await Future.wait([
      db.recordChapterUpdates(manga, [chapter(1), chapter(2)]),
      other.recordChapterUpdates(manga, [chapter(1), chapter(2)]),
    ]);
    expect(results.expand((r) => r), hasLength(1));
    expect(await db.getUnseenUpdateCount(), 1);
  });
  test('shared check notifies once then remains idempotent', () async {
    await raw.insert('chapters', chapter(1).toMap());
    var notifications = 0;
    final service = LibraryUpdateService.forTesting(
      database: db,
      fetch: (_) async => [chapter(1), chapter(2)],
      notify: (_, added) async {
        notifications++;
        expect(added, hasLength(1));
      },
    );
    expect(await service.checkForUpdates(), 1);
    expect(service.unseenUpdateCount.value, 1);
    expect(await service.checkForUpdates(), 0);
    expect(notifications, 1);
    expect(service.isCheckingUpdates.value, false);
  });
  test('silent check persists updates without OS notification', () async {
    await raw.insert('chapters', chapter(1).toMap());
    final service = LibraryUpdateService.forTesting(
      database: db,
      fetch: (_) async => [chapter(2)],
      notify: (_, _) async => fail('must stay silent'),
    );
    expect(await service.checkForUpdates(silent: true), 1);
    expect(await db.getUnseenUpdateCount(), 1);
  });
  test('failed fetch is visible and checking state resets', () async {
    final service = LibraryUpdateService.forTesting(
      database: db,
      fetch: (_) async => throw StateError('offline'),
      notify: (_, _) async {},
    );
    await expectLater(service.checkForUpdates(), throwsStateError);
    expect(service.isCheckingUpdates.value, false);
    expect(await db.getUnseenUpdateCount(), 0);
    expect(await db.getLibraryUpdateCursor(), 'm');
  });
  test('exhausted budget does not start network work', () async {
    final service = LibraryUpdateService.forTesting(
      database: db,
      fetch: (_) async {
        fail('budget exhausted');
      },
      notify: (_, _) async {},
    );
    await expectLater(
      service.checkForUpdates(budget: Duration.zero),
      throwsStateError,
    );
    expect(service.isCheckingUpdates.value, false);
  });
  test(
    'timed out network cannot write chapters after task completes',
    () async {
      final pending = Completer<List<MangaChapter>>();
      final service = LibraryUpdateService.forTesting(
        database: db,
        fetch: (_) => pending.future,
        notify: (_, _) async => fail('late notification'),
      );
      await expectLater(
        service.checkForUpdates(budget: const Duration(milliseconds: 2020)),
        throwsStateError,
      );
      pending.complete([chapter(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(await db.getChapters('m'), isEmpty);
    },
  );
}
