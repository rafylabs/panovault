import '../database/models/manga.dart';
import '../database/models/chapter.dart';
import '../database/models/manga_page.dart';

abstract class MangaParser {
  String get id;
  String get name;
  String get domain;
  String get locale;
  String get iconUrl => 'https://$domain/favicon.ico';

  Map<String, String> get headers => {
    'Referer': 'https://$domain/',
  };

  List<String> get availableCategories => const ['All', 'Manhwa', 'Manga', 'Manhua'];
  List<String> get availableGenres => const [
    'All',
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Horror',
    'Isekai',
    'Martial Arts',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Supernatural',
    'Thriller',
  ];

  Future<List<Manga>> getList({
    required int page,
    required SortOrder order,
    String? query,
    String? genre,
    List<String>? genres,
    String? category,
  });

  Future<Manga> getDetails(Manga manga);

  Future<List<MangaChapter>> getChapters(Manga manga);

  /// Update jobs must distinguish source failures from a valid empty catalog.
  /// Fail closed until a parser explicitly implements strict fetching; reader
  /// methods may intentionally swallow errors or return incomplete catalogs.
  Future<List<MangaChapter>> getChaptersForUpdates(Manga manga) async =>
      throw UnsupportedError('Strict chapter updates are not supported by $id');

  Future<List<MangaPage>> getPages(MangaChapter chapter);
}
