import 'package:equatable/equatable.dart';

enum NoticeCategory { course, exam, scholarship, holiday, general }

class SchoolNotice extends Equatable {
  const SchoolNotice({
    required this.id,
    required this.title,
    required this.summary,
    required this.publishedAt,
    required this.category,
    required this.source,
    this.keywords = const [],
    this.pinned = false,
    this.url,
    this.live = false,
  });

  final String id;
  final String title;
  final String summary;
  final DateTime publishedAt;
  final NoticeCategory category;
  final String source;
  final List<String> keywords;
  final bool pinned;
  final String? url;
  final bool live;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'publishedAt': publishedAt.toIso8601String(),
        'category': category.name,
        'source': source,
        'keywords': keywords,
        'pinned': pinned,
        'url': url,
        'live': live,
      };

  factory SchoolNotice.fromJson(Map<String, dynamic> json) {
    final catRaw = json['category'] as String? ?? 'general';
    final category = NoticeCategory.values.firstWhere(
      (c) => c.name == catRaw,
      orElse: () => NoticeCategory.general,
    );
    final keywordsRaw = json['keywords'];
    final keywords = <String>[];
    if (keywordsRaw is List) {
      for (final k in keywordsRaw) {
        if (k is String) keywords.add(k);
      }
    }
    return SchoolNotice(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      category: category,
      source: json['source'] as String? ?? '',
      keywords: keywords,
      pinned: json['pinned'] as bool? ?? false,
      url: json['url'] as String?,
      live: json['live'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        summary,
        publishedAt,
        category,
        source,
        keywords,
        pinned,
        url,
        live,
      ];
}

class NoticesSnapshot {
  const NoticesSnapshot({
    required this.notices,
    required this.live,
    this.banner,
    this.fromCache = false,
    this.cachedAt,
    this.fetchedAt,
  });

  final List<SchoolNotice> notices;
  final bool live;
  final String? banner;
  final bool fromCache;
  final DateTime? cachedAt;
  final DateTime? fetchedAt;

  NoticesSnapshot copyWith({
    List<SchoolNotice>? notices,
    bool? live,
    String? banner,
    bool? fromCache,
    DateTime? cachedAt,
    DateTime? fetchedAt,
    bool clearBanner = false,
    bool clearCachedAt = false,
    bool clearFetchedAt = false,
  }) {
    return NoticesSnapshot(
      notices: notices ?? this.notices,
      live: live ?? this.live,
      banner: clearBanner ? null : (banner ?? this.banner),
      fromCache: fromCache ?? this.fromCache,
      cachedAt: clearCachedAt ? null : (cachedAt ?? this.cachedAt),
      fetchedAt: clearFetchedAt ? null : (fetchedAt ?? this.fetchedAt),
    );
  }

  NoticesSnapshot asCached(DateTime savedAt, {required String banner}) =>
      copyWith(
        fromCache: true,
        cachedAt: savedAt,
        banner: banner,
        clearFetchedAt: true,
      );

  NoticesSnapshot asFresh({String? banner}) => copyWith(
        fromCache: false,
        fetchedAt: DateTime.now(),
        banner: banner ?? this.banner,
        clearCachedAt: true,
      );

  Map<String, dynamic> toJson() => {
        'notices': notices.map((n) => n.toJson()).toList(),
        'live': live,
        if (banner != null) 'banner': banner,
      };

  factory NoticesSnapshot.fromJson(Map<String, dynamic> json) {
    final noticesRaw = json['notices'];
    final notices = <SchoolNotice>[];
    if (noticesRaw is List) {
      for (final item in noticesRaw) {
        if (item is Map) {
          notices.add(SchoolNotice.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return NoticesSnapshot(
      notices: notices,
      live: json['live'] as bool? ?? true,
      banner: json['banner'] as String?,
    );
  }
}
