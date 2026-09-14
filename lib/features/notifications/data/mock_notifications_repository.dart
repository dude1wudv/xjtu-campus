import '../domain/notice_filter.dart';
import '../domain/notifications_repository.dart';
import '../domain/school_notice.dart';

class MockNotificationsRepository implements NotificationsRepository {
  static final notices = [
    SchoolNotice(
      id: 'n1',
      title: '关于 2026-2027 学年第一学期补退选安排的通知',
      summary: '补退选将于第 2 周开放，请核对本学期课表后再调整志愿。',
      publishedAt: DateTime(2026, 9, 10, 9),
      category: NoticeCategory.course,
      source: '教务处',
      keywords: ['补退选', '课表'],
      pinned: true,
    ),
    SchoolNotice(
      id: 'n2',
      title: '高等数学A 期中测验时间预告',
      summary: '第 8 周周六上午，考场详见后续通知。请携带学生证。',
      publishedAt: DateTime(2026, 9, 12, 16, 30),
      category: NoticeCategory.exam,
      source: '数学与统计学院',
      keywords: ['高等数学A', '期中'],
    ),
    SchoolNotice(
      id: 'n3',
      title: '国家奖学金评审材料提交提醒',
      summary: '请在本周五 17:00 前通过办事大厅提交成绩单与综述。',
      publishedAt: DateTime(2026, 9, 11, 11),
      category: NoticeCategory.scholarship,
      source: '学生处',
      keywords: ['奖学金'],
    ),
    SchoolNotice(
      id: 'n4',
      title: '中秋、国庆放假安排',
      summary: '具体调休以学校办公室最新通知为准，实验室需提前报备。',
      publishedAt: DateTime(2026, 9, 8, 8, 30),
      category: NoticeCategory.holiday,
      source: '学校办公室',
      keywords: ['放假'],
    ),
    SchoolNotice(
      id: 'n5',
      title: '创新港班车时刻微调',
      summary: '工作日 7:10 兴庆首班不变，晚间末班延后 10 分钟。',
      publishedAt: DateTime(2026, 9, 13, 18),
      category: NoticeCategory.general,
      source: '后勤保障部',
      keywords: ['班车', '创新港'],
    ),
  ];

  @override
  Future<List<SchoolNotice>> fetchNotices({NoticeFilterRule? rule}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final filtered = notices.where((notice) => rule?.matches(notice) ?? true);
    final list = filtered.toList()
      ..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return list;
  }
}
