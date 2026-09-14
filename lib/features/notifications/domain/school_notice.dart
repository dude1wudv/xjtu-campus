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
  });

  final String id;
  final String title;
  final String summary;
  final DateTime publishedAt;
  final NoticeCategory category;
  final String source;
  final List<String> keywords;
  final bool pinned;

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
  ];
}
