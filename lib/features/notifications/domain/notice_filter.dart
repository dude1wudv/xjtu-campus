import 'school_notice.dart';

/// 教务通知本地规则。后续可结合课表生成个性化提醒。
class NoticeFilterRule {
  const NoticeFilterRule({
    this.category,
    this.keyword,
    this.courseNames = const [],
  });

  final NoticeCategory? category;
  final String? keyword;
  final List<String> courseNames;

  bool matches(SchoolNotice notice) {
    if (category != null && notice.category != category) return false;
    final keyword = this.keyword?.trim();
    if (keyword != null && keyword.isNotEmpty) {
      final haystack = '${notice.title}${notice.summary}${notice.keywords.join()}';
      if (!haystack.contains(keyword)) return false;
    }
    if (courseNames.isNotEmpty) {
      final hit = courseNames.any(
        (name) => notice.title.contains(name) || notice.summary.contains(name),
      );
      if (!hit && notice.category == NoticeCategory.course) return false;
    }
    return true;
  }
}

extension NoticeCategoryLabel on NoticeCategory {
  String get label => switch (this) {
    NoticeCategory.course => '选课',
    NoticeCategory.exam => '考试',
    NoticeCategory.scholarship => '奖助',
    NoticeCategory.holiday => '假期',
    NoticeCategory.general => '综合',
  };
}
