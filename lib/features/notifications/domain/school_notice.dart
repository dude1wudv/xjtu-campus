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
  });

  final List<SchoolNotice> notices;
  final bool live;
  final String? banner;
}
