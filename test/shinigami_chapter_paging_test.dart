import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panovault/core/database/models/manga.dart';
import 'package:panovault/core/network/http_client.dart';
import 'package:panovault/core/parser/parsers/shinigami_parser.dart';

class _ChapterPagingAdapter implements HttpClientAdapter {
  _ChapterPagingAdapter({this.repeatCursor = false, this.missingCursor = false});

  final bool repeatCursor;
  final bool missingCursor;
  final requestedCursors = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final cursor = options.uri.queryParameters['cursor'];
    requestedCursors.add(cursor);
    final firstPage = cursor == null;
    final chapters = firstPage
        ? [
            {'chapter_id': 'ch-10', 'chapter_number': 10},
            {'chapter_id': 'ch-9', 'chapter_number': 9},
          ]
        : [
            {'chapter_id': 'ch-9', 'chapter_number': 9},
            {'chapter_id': 'ch-8', 'chapter_number': 8},
          ];
    final payload = {
      'data': chapters,
      'meta': {
        'has_next': firstPage || repeatCursor || missingCursor,
        if (firstPage && !missingCursor) 'next_cursor': 'page-2-cursor',
        if (!firstPage && repeatCursor) 'next_cursor': 'page-2-cursor',
      },
    };
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Shinigami chapter pagination follows next_cursor without duplicates',
    () async {
      final dio = PanovaultHttpClient.instance.dio;
      final originalAdapter = dio.httpClientAdapter;
      final adapter = _ChapterPagingAdapter();
      dio.httpClientAdapter = adapter;
      try {
        final manga = Manga(
          id: 'shinigami_manga-uuid',
          title: 'Test manga',
          url: 'manga-uuid',
          coverUrl: '',
          sourceId: 'shinigami',
        );
        final chapters = await ShinigamiParser().getChapters(manga);

        expect(adapter.requestedCursors, [null, 'page-2-cursor']);
        expect(chapters.map((chapter) => chapter.url), [
          'ch-10',
          'ch-9',
          'ch-8',
        ]);
      } finally {
        dio.httpClientAdapter = originalAdapter;
      }
    },
  );

  for (final scenario in ['repeated', 'missing']) {
    test('Shinigami pagination stops on $scenario next cursor', () async {
      final dio = PanovaultHttpClient.instance.dio;
      final originalAdapter = dio.httpClientAdapter;
      final adapter = _ChapterPagingAdapter(
        repeatCursor: scenario == 'repeated',
        missingCursor: scenario == 'missing',
      );
      dio.httpClientAdapter = adapter;
      try {
        final manga = Manga(
          id: 'shinigami_manga-uuid',
          title: 'Test manga',
          url: 'manga-uuid',
          coverUrl: '',
          sourceId: 'shinigami',
        );
        final chapters = await ShinigamiParser().getChapters(manga);

        expect(
          adapter.requestedCursors,
          scenario == 'repeated' ? [null, 'page-2-cursor'] : [null],
        );
        expect(
          chapters.map((chapter) => chapter.url),
          scenario == 'repeated' ? ['ch-10', 'ch-9', 'ch-8'] : ['ch-10', 'ch-9'],
        );
      } finally {
        dio.httpClientAdapter = originalAdapter;
      }
    });
  }
}
