import '../../database/models/manga.dart';
import '../../database/models/chapter.dart';
import '../../database/models/manga_page.dart';
import '../../network/http_client.dart';
import '../manga_parser.dart';

class ShinigamiParser extends MangaParser {
  // ignore: prefer_initializing_formals
  ShinigamiParser({String? customDomain}) : _customDomain = customDomain;

  String? _customDomain;

  /// Accepts raw manga uuid, prefixed DB id (`shinigami_<uuid>`), or full URL.
  String _mangaId(Manga manga) {
    final raw = manga.url.trim();
    if (raw.contains('/manga/')) {
      final segs = Uri.parse(raw).pathSegments;
      final i = segs.indexOf('manga');
      if (i >= 0 && segs.length > i + 1) return segs[i + 1];
    }
    final prefix = '${id}_';
    if (raw.startsWith(prefix)) return raw.substring(prefix.length);
    return raw;
  }

  void setCustomDomain(String newDomain) {
    _customDomain = newDomain
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('/', '')
        .trim();
  }

  @override
  String get id => 'shinigami';

  @override
  String get name => 'Shinigami (ID)';

  @override
  String get domain => _customDomain ?? 's1.shinigami.mx';

  @override
  String get locale => 'id';

  static const String _apiBase = 'https://api.shinigami.io/v1';
  static const String _cdnBase = 'https://cdn.shinigami.gg';
  static const int _listPageSize = 24;
  static const int _chapterPageSize = 100;

  @override
  Map<String, String> get headers => {
        'Referer': 'https://$domain/',
        'Origin': 'https://$domain',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
      };

  @override
  List<String> get availableCategories => const [
        'All',
        'Manhwa',
        'Manga',
        'Manhua',
        'Project',
        'Mirror',
      ];

  @override
  List<String> get availableGenres => const [
        'All',
        'Action',
        'Adventure',
        'Comedy',
        'Cooking',
        'Crime',
        'Demon',
        'Drama',
        'Ecchi',
        'Fantasy',
        'Fight',
        'Game',
        'Gender Bender',
        'Harem',
        'Historical',
        'Horror',
        'Isekai',
        'Josei',
        'Magic',
        'Martial Arts',
        'Mature',
        'Mecha',
        'Medical',
        'Murim',
        'Mystery',
        'Psychological',
        'Regression',
        'Reincarnation',
        'Revenge',
        'Romance',
        'School Life',
        'Sci-fi',
        'Seinen',
        'Shoujo',
        'Shounen',
        'Slice of Life',
        'Sports',
        'Supernatural',
        'Thriller',
        'Tragedy',
        'Wuxia',
      ];

  static const Map<String, String> _genreSlugMap = {
    'action': 'action',
    'adult': 'adult',
    'adventure': 'adventure',
    'comedy': 'comedy',
    'cooking': 'cooking',
    'crime': 'crime',
    'demon': 'demon',
    'drama': 'drama',
    'ecchi': 'ecchi',
    'fantasy': 'fantasy',
    'fight': 'fight',
    'game': 'game',
    'gender bender': 'gender-bender',
    'harem': 'harem',
    'historical': 'historical',
    'horror': 'horror',
    'isekai': 'isekai',
    'josei': 'josei-genre',
    'magic': 'magic',
    'martial arts': 'martial-arts',
    'mature': 'mature',
    'mecha': 'mecha',
    'medical': 'medical',
    'murim': 'murim',
    'mystery': 'mystery',
    'psychological': 'psychological',
    'regression': 'regression',
    'reincarnation': 'reincarnation-genre',
    'revenge': 'revenge',
    'romance': 'romance',
    'school life': 'school-life',
    'sci-fi': 'sci-fi',
    'seinen': 'seinen',
    'shoujo': 'shoujo',
    'shounen': 'shounen',
    'slice of life': 'slice-of-life',
    'smut': 'smut',
    'sports': 'sports',
    'supernatural': 'supernatural',
    'thriller': 'thriller',
    'tragedy': 'tragedy',
    'wuxia': 'wuxia',
  };

  String _toGenreSlug(String genre) {
    final lower = genre.trim().toLowerCase();
    return _genreSlugMap[lower] ?? lower.replaceAll(' ', '-');
  }

  String _absolutize(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return v.startsWith('/') ? '$_cdnBase$v' : '$_cdnBase/$v';
  }

  MangaStatus _parseStatus(dynamic raw) {
    if (raw == 1 || raw == '1') return MangaStatus.ongoing;
    if (raw == 2 || raw == '2') return MangaStatus.completed;
    if (raw == 3 || raw == '3') return MangaStatus.cancelled;
    return MangaStatus.unknown;
  }

  Manga _mangaFromJson(Map<String, dynamic> item) {
    final mId = (item['manga_id'] as String?)?.trim() ?? '';
    final title = (item['title'] as String?)?.trim() ?? '';

    final portrait = (item['cover_portrait_url'] as String?) ?? '';
    final cover = (item['cover_image_url'] as String?) ?? '';
    final coverUrl = _absolutize(
      portrait.trim().isNotEmpty ? portrait : cover,
    );

    return Manga(
      id: '${id}_$mId',
      title: title,
      altTitle: item['alternative_title'] as String?,
      url: mId,
      coverUrl: coverUrl,
      sourceId: id,
      status: _parseStatus(item['status']),
      description: item['description'] as String?,
    );
  }

  @override
  Future<List<Manga>> getList({
    required int page,
    required SortOrder order,
    String? query,
    String? genre,
    List<String>? genres,
    String? category,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final offset = (safePage - 1) * _listPageSize;
    final sort = order == SortOrder.popular ? 'popularity' : 'latest';

    final params = <String>[
      'offset=$offset',
      'limit=$_listPageSize',
      'sort=$sort',
      'sort_order=desc',
    ];

    if (query != null && query.trim().isNotEmpty) {
      params.add('q=${Uri.encodeQueryComponent(query.trim())}');
    }

    if (category != null &&
        category.trim().isNotEmpty &&
        category.trim().toLowerCase() != 'all') {
      final cat = category.trim().toLowerCase();
      if (cat == 'project' || cat == 'mirror') {
        params.add('type=$cat');
      } else {
        params.add('format=$cat');
      }
    }

    final activeSlugs = <String>{};
    if (genres != null && genres.isNotEmpty) {
      for (final g in genres) {
        if (g.trim().isNotEmpty && g.trim().toLowerCase() != 'all') {
          activeSlugs.add(_toGenreSlug(g));
        }
      }
    } else if (genre != null &&
        genre.trim().isNotEmpty &&
        genre.trim().toLowerCase() != 'all') {
      activeSlugs.add(_toGenreSlug(genre));
    }
    for (final slug in activeSlugs) {
      params.add('genre=${Uri.encodeQueryComponent(slug)}');
    }

    try {
      final res = await PanovaultHttpClient.instance.get<Map<String, dynamic>>(
        '$_apiBase/manga/list?${params.join('&')}',
        headers: headers,
      );

      final dataList = res.data?['data'] as List<dynamic>? ?? <dynamic>[];
      final list = <Manga>[];
      for (final item in dataList) {
        if (item is! Map<String, dynamic>) continue;
        final manga = _mangaFromJson(item);
        if (manga.url.isEmpty || manga.title.isEmpty) continue;
        list.add(manga);
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<Manga> getDetails(Manga manga) async {
    try {
      final res = await PanovaultHttpClient.instance.get<Map<String, dynamic>>(
        '$_apiBase/manga/detail/${_mangaId(manga)}',
        headers: headers,
      );

      final data = res.data?['data'] as Map<String, dynamic>?;
      if (data == null) return manga;

      final tax = data['taxonomy'] as Map<String, dynamic>?;
      List<String> names(String key) {
        final raw = tax?[key] as List<dynamic>?;
        if (raw == null) return const [];
        return raw
            .whereType<Map<String, dynamic>>()
            .map((e) => e['name'])
            .whereType<String>()
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }

      final genres = names('Genre');
      final authors = names('Author');
      final artists = names('Artist');

      final altTitle = (data['alternative_title'] as String?)?.trim();
      final coverUrl = _absolutize(
        ((data['cover_portrait_url'] as String?)?.trim().isNotEmpty ?? false)
            ? data['cover_portrait_url'] as String
            : (data['cover_image_url'] as String? ?? ''),
      );

      return manga.copyWith(
        description: (data['description'] as String?) ?? manga.description,
        genres: genres.isNotEmpty ? genres : manga.genres,
        coverUrl: coverUrl.isNotEmpty ? coverUrl : manga.coverUrl,
        author: authors.isNotEmpty ? authors.join(', ') : manga.author,
        artist: artists.isNotEmpty ? artists.join(', ') : manga.artist,
        altTitle: (altTitle != null && altTitle.isNotEmpty)
            ? altTitle
            : manga.altTitle,
        status: _parseStatus(data['status']),
      );
    } catch (_) {
      return manga;
    }
  }

  @override
  Future<List<MangaChapter>> getChapters(Manga manga) =>
      _getChapters(manga, strict: false);

  @override
  Future<List<MangaChapter>> getChaptersForUpdates(Manga manga) =>
      _getChapters(manga, strict: true);

  Future<List<MangaChapter>> _getChapters(Manga manga, {required bool strict}) async {
    final mId = _mangaId(manga);
    final chapters = <MangaChapter>[];
    final seenChapterIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    var guard = 0;

    try {
      while (guard++ < 40) {
        final url = '$_apiBase/chapter/$mId/list'
            '?limit=$_chapterPageSize'
            '&sort_by=chapter_number&sort_order=desc'
            '${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}';

        final res =
            await PanovaultHttpClient.instance.get<Map<String, dynamic>>(
          url,
          headers: headers,
        );

        if (strict && res.data?['data'] is! List) {
          throw const FormatException('Invalid Shinigami chapter list');
        }
        final meta = res.data?['meta'] as Map<String, dynamic>?;
        if (strict && (meta == null || meta['has_next'] is! bool)) {
          throw const FormatException('Invalid Shinigami pagination metadata');
        }
        final dataList = res.data?['data'] as List<dynamic>? ?? <dynamic>[];
        if (strict && dataList.isEmpty && meta?['has_next'] == true) {
          throw const FormatException('Empty Shinigami page has a continuation');
        }
        if (dataList.isEmpty) break;

        for (final item in dataList) {
          if (strict && (item is! Map<String, dynamic> ||
              item['chapter_id'] is! String ||
              (item['chapter_id'] as String).trim().isEmpty ||
              item['chapter_number'] is! num ||
              !(item['chapter_number'] as num).isFinite)) {
            throw const FormatException('Invalid Shinigami chapter entry');
          }
          if (item is! Map<String, dynamic>) continue;
          final chId = (item['chapter_id'] as String?)?.trim() ?? '';
          if (chId.isEmpty || !seenChapterIds.add(chId)) continue;

          final chNum = (item['chapter_number'] as num?)?.toDouble() ?? 0.0;
          final rawTitle = (item['chapter_title'] as String?)?.trim() ?? '';
          final title =
              rawTitle.isNotEmpty ? 'Chapter $chNum: $rawTitle' : 'Chapter $chNum';

          final releaseDateStr =
              (item['release_date'] as String?) ?? (item['created_at'] as String?);

          chapters.add(MangaChapter(
            id: '${id}_${manga.id}_$chId',
            mangaId: manga.id,
            title: title,
            number: chNum,
            url: chId,
            uploadDate:
                releaseDateStr != null ? DateTime.tryParse(releaseDateStr) : null,
          ));
        }

        final hasNext = meta?['has_next'] == true;
        if (!hasNext) break;
        final nextCursor = (meta?['next_cursor'] as String?)?.trim();
        if (nextCursor == null || nextCursor.isEmpty || !seenCursors.add(nextCursor)) {
          if (strict) {
            throw const FormatException('Missing or repeated Shinigami cursor');
          }
          break;
        }
        cursor = nextCursor;
        if (strict && guard == 40) {
          throw const FormatException('Shinigami chapter pagination limit reached');
        }
      }

      chapters.sort((a, b) => b.number.compareTo(a.number));
      return chapters;
    } catch (_) {
      if (strict) rethrow;
      return chapters;
    }
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    try {
      final res = await PanovaultHttpClient.instance.get<Map<String, dynamic>>(
        '$_apiBase/chapter/detail/${chapter.url}',
        headers: headers,
      );

      final data = res.data?['data'] as Map<String, dynamic>?;
      if (data == null) return [];

      final chData = data['chapter'] as Map<String, dynamic>?;
      if (chData == null) return [];

      final base = _absolutize((data['base_url'] as String?) ?? '');
      final baseUrl = base.isEmpty ? _cdnBase : base;
      final path = (chData['path'] as String?) ?? '';
      final images = chData['data'] as List<dynamic>? ?? <dynamic>[];

      final pages = <MangaPage>[];
      for (var i = 0; i < images.length; i++) {
        final file = images[i];
        if (file is! String || file.trim().isEmpty) continue;
        final prefix = path.startsWith('/') ? path : '/$path';
        pages.add(MangaPage(
          index: pages.length,
          url: '$baseUrl$prefix${file.trim()}',
          headers: headers,
        ));
      }
      return pages;
    } catch (_) {
      return [];
    }
  }
}
