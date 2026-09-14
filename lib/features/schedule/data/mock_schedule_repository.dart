import '../../../core/l10n/app_strings.dart';
import '../domain/course.dart';
import '../domain/schedule_repository.dart';
import 'mock_schedule_data.dart';

class MockScheduleRepository implements ScheduleRepository {
  MockScheduleRepository({this.termStart});

  final DateTime? termStart;

  DateTime get _termStart =>
      termStart ?? DateTime.parse(MockScheduleData.termStart);

  @override
  Future<int> currentWeek({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final start = DateTime(_termStart.year, _termStart.month, _termStart.day);
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(start).inDays;
    if (days < 0) return 1;
    return (days ~/ 7) + 1;
  }

  @override
  Future<List<Course>> fetchCourses() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return List<Course>.unmodifiable(MockScheduleData.courses);
  }

  @override
  Future<ScheduleSnapshot> load({DateTime? now}) async {
    return ScheduleSnapshot(
      courses: await fetchCourses(),
      week: await currentWeek(now: now),
      live: false,
      banner: AppStrings.mockBanner,
      termStart: _termStart,
    );
  }
}
