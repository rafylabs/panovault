import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panovault/core/database/models/manga.dart';
import 'package:panovault/core/network/http_client.dart';

import 'package:panovault/core/parser/parser_registry.dart';
import 'package:panovault/core/parser/parsers/komiku_parser.dart';
import 'package:panovault/core/services/background_library_updates.dart';

const _manga = Manga(
  id: 'm',
  title: 'Test',
  url: 'https://example.com/series/m',
  coverUrl: '',
  sourceId: 'test',
);

Map<String, dynamic> _entry(int n) => {
  'chapter_id': 'c$n',
  'chapter_number': n,
};
Map<String, dynamic> _page(List<dynamic> entries, {String? next}) => {
  'data': entries,
  'meta': {'has_next': next != null, 'next_cursor': next},
};

void _intercept(dynamic Function(RequestOptions) response) {
  final interceptor = InterceptorsWrapper(
    onRequest: (options, handler) {
      try {
        final data = response(options);
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: data,
          ),
        );
      } on DioException catch (error) {
        handler.reject(error);
      }
    },
  );
  PanovaultHttpClient.instance.dio.interceptors.insert(0, interceptor);
  addTearDown(
    () => PanovaultHttpClient.instance.dio.interceptors.remove(interceptor),
  );
}

Never _offline(RequestOptions options) => throw DioException(
  requestOptions: options,
  type: DioExceptionType.connectionError,
  error: 'offline',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => ParserRegistry.instance.resetForTesting());
  tearDown(() => ParserRegistry.instance.resetForTesting());

  test('registry audit covers every registered built-in', () {
    expect(ParserRegistry.instance.allParsers.map((p) => p.id).toSet(), {
      'mangapill',
      'shinigami',
      'weebcentral',
    });
  });

  test(
    'unregistered legacy Komiku fails closed rather than silently fetching',
    () async {
      var requests = 0;
      _intercept((_) {
        requests++;
        return '<html></html>';
      });
      await expectLater(
        KomikuParser().getChaptersForUpdates(_manga),
        throwsUnsupportedError,
      );
      expect(requests, 0);
    },
  );

  for (final id in ['mangapill', 'shinigami', 'weebcentral']) {
    test('$id request failure reaches dispatcher through strict API', () async {
      final parser = ParserRegistry.instance.getParser(id)!;
      _intercept(_offline);
      expect(
        await dispatchLibraryUpdate(
          libraryUpdateTask,
          initialize: () async {},
          check: () async {
            await parser.getChaptersForUpdates(_manga);
          },
        ),
        false,
      );
      if (id != 'mangapill') {
        expect(await parser.getChapters(_manga), isEmpty);
      } else {
        // MangaPill already propagated reader request errors before this change.
        await expectLater(
          parser.getChapters(_manga),
          throwsA(isA<DioException>()),
        );
      }
    });

    test('$id accepts a valid empty catalog', () async {
      final parser = ParserRegistry.instance.getParser(id)!;
      _intercept(
        (_) => id == 'shinigami' ? _page([]) : '<html><body></body></html>',
      );
      expect(await parser.getChaptersForUpdates(_manga), isEmpty);
    });

    test(
      '$id rejects missing response rather than reporting empty success',
      () async {
        final parser = ParserRegistry.instance.getParser(id)!;
        _intercept((_) => null);
        await expectLater(
          parser.getChaptersForUpdates(_manga),
          throwsFormatException,
        );
        expect(await parser.getChapters(_manga), isEmpty);
      },
    );

    test('$id parses valid chapters through production HTTP client', () async {
      final parser = ParserRegistry.instance.getParser(id)!;
      _intercept((options) {
        if (id == 'shinigami') {
          expect(options.uri.path, contains('/chapter/'));
          return _page([_entry(2), _entry(1)]);
        }
        if (id == 'weebcentral') {
          expect(options.uri.path, endsWith('/full-chapter-list'));
        }
        return '<div id="chapters"><a href="/chapters/c2"><span>Chapter 2</span></a>'
            '<a href="/chapters/c1"><span>Chapter 1</span></a></div>';
      });
      final chapters = await parser.getChaptersForUpdates(_manga);
      expect(chapters.map((c) => c.number), [2.0, 1.0]);
      expect(chapters.map((c) => c.id), ['${id}_m_c2', '${id}_m_c1']);
    });
  }

  for (final id in ['mangapill', 'weebcentral']) {
    test('$id rejects malformed chapter link after a valid entry', () async {
      final parser = ParserRegistry.instance.getParser(id)!;
      _intercept(
        (_) =>
            '<div id="chapters">'
            '<a href="/chapters/c2"><span>Chapter 2</span></a>'
            '<a href="/chapters/"><span>Chapter 1</span></a></div>',
      );
      if (id == 'mangapill') {
        // Missing href is invalid for MangaPill; WeebCentral selects by href.
        _intercept(
          (_) =>
              '<div id="chapters"><a href="/chapters/c2">Chapter 2</a>'
              '<a>Chapter 1</a></div>',
        );
      }
      await expectLater(
        parser.getChaptersForUpdates(_manga),
        throwsFormatException,
      );
      expect(await parser.getChapters(_manga), isNotEmpty);
    });
  }

  for (final failure in [
    'json',
    'missing-list',
    'wrong-list',
    'entry',
    'missing-id',
    'missing-number',
    'missing-meta',
    'wrong-meta',
    'wrong-has-next',
    'missing-cursor',
    'repeated-cursor',
    'empty-continuation',
    'network-page-two',
    'malformed-page-two',
    'pagination-limit',
  ]) {
    test(
      'shinigami rejects $failure without returning partial chapters',
      () async {
        final parser = ParserRegistry.instance.getParser('shinigami')!;
        var requests = 0;
        _intercept((options) {
          requests++;
          final cursor = options.uri.queryParameters['cursor'];
          switch (failure) {
            case 'json':
              return '{bad';
            case 'missing-list':
              return {
                'meta': {'has_next': false},
              };
            case 'wrong-list':
              return {'data': 'invalid'};
            case 'entry':
              return _page([_entry(2), 42]);
            case 'missing-id':
              return _page([
                {'chapter_number': 1},
              ]);
            case 'missing-number':
              return _page([
                {'chapter_id': 'c1'},
              ]);
            case 'missing-meta':
              return {
                'data': [_entry(1)],
              };
            case 'wrong-meta':
              return {'data': [], 'meta': 'bad'};
            case 'wrong-has-next':
              return {
                'data': [],
                'meta': {'has_next': 'yes'},
              };
            case 'missing-cursor':
              return {
                'data': [_entry(1)],
                'meta': {'has_next': true},
              };
            case 'repeated-cursor':
              return _page([_entry(1)], next: 'again');
            case 'empty-continuation':
              return _page([], next: 'next');
            case 'network-page-two':
              if (cursor != null) return _offline(options);
              return _page([_entry(2)], next: 'next');
            case 'malformed-page-two':
              if (cursor != null) {
                return _page([
                  {'chapter_number': 1},
                ]);
              }
              return _page([_entry(2)], next: 'next');
            case 'pagination-limit':
              return _page([_entry(requests)], next: 'cursor$requests');
          }
          throw StateError('Unhandled fixture');
        });
        await expectLater(
          parser.getChaptersForUpdates(_manga),
          throwsA(
            anyOf(
              isA<FormatException>(),
              isA<TypeError>(),
              isA<DioException>(),
            ),
          ),
        );
        if (failure == 'network-page-two' ||
            failure == 'malformed-page-two' ||
            failure == 'repeated-cursor') {
          expect(requests, 2);
          final reader = await parser.getChapters(_manga);
          expect(reader, hasLength(1));
          expect(reader.single.number, failure == 'repeated-cursor' ? 1 : 2);
        }
        if (failure == 'pagination-limit') expect(requests, 40);
      },
    );
  }

  test(
    'shinigami follows cursor and returns a complete sorted catalog',
    () async {
      final parser = ParserRegistry.instance.getParser('shinigami')!;
      final cursors = <String?>[];
      _intercept((options) {
        final cursor = options.uri.queryParameters['cursor'];
        cursors.add(cursor);
        return cursor == null
            ? _page([_entry(2)], next: 'next / cursor')
            : _page([_entry(1)]);
      });
      final chapters = await parser.getChaptersForUpdates(_manga);
      expect(cursors, [null, 'next / cursor']);
      expect(chapters.map((c) => c.number), [2, 1]);
    },
  );

  test(
    'shinigami accepts a terminal empty page after populated page',
    () async {
      final parser = ParserRegistry.instance.getParser('shinigami')!;
      _intercept(
        (options) => options.uri.queryParameters['cursor'] == null
            ? _page([_entry(1)], next: 'end')
            : _page([]),
      );
      expect(await parser.getChaptersForUpdates(_manga), hasLength(1));
    },
  );
}
