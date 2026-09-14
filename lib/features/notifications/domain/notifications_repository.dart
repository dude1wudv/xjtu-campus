import 'notice_filter.dart';
import 'school_notice.dart';

abstract class NotificationsRepository {
  Future<List<SchoolNotice>> fetchNotices({NoticeFilterRule? rule});

  Future<NoticesSnapshot> load({NoticeFilterRule? rule});
}
