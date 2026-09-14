import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xjtu_campus/core/cache/snapshot_cache.dart';
import 'package:xjtu_campus/core/l10n/app_strings.dart';
import 'package:xjtu_campus/features/grades/domain/grade_record.dart';
import 'package:xjtu_campus/features/schedule/domain/course.dart';
import 'package:xjtu_campus/features/schedule/domain/schedule_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('ScheduleSnapshot cache roundtrip preserves courses and week', () async {
    final cache = SnapshotCache(await SharedPreferences.getInstance());
    final snap = ScheduleSnapshot(
      courses: [
        Course(
          id: 'c1',
          name: '高等数学',
          teacher: '张老师',
          campus: '兴庆校区',
          building: '主楼A',
          room: '101',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: const [1, 2, 3],
          weeksLabel: '1-3周',
        ),
      ],
      week: 5,
      live: true,
      banner: AppStrings.liveBanner,
      termStart: DateTime.utc(2026, 9, 1),
    );

    await cache.write(SnapshotCache.schedule, snap.toJson());
    final envelope =
        await cache.readEnvelope(SnapshotCache.schedule, ScheduleSnapshot.fromJson);
    expect(envelope, isNotNull);
    expect(envelope!.payload.live, isTrue);
    expect(envelope.payload.week, 5);
    expect(envelope.payload.courses, hasLength(1));
    expect(envelope.payload.courses.first.name, '高等数学');
    expect(envelope.payload.courses.first.weeks, [1, 2, 3]);
    expect(envelope.payload.termStart?.toUtc(), DateTime.utc(2026, 9, 1));
    expect(envelope.savedAt, isA<DateTime>());
  });

  test('GradesSnapshot cache roundtrip; demo not written by caller contract',
      () async {
    final cache = SnapshotCache(await SharedPreferences.getInstance());
    final snap = GradesSnapshot(
      records: const [
        GradeRecord(
          termCode: '2025-2026-2',
          courseName: '线性代数',
          credit: 3,
          gpaPoints: 4.0,
          score: '90',
          courseCode: 'MATH101',
        ),
      ],
      live: true,
      banner: AppStrings.liveBanner,
      groupedByTerm: const {
        '2025-2026-2': [
          GradeRecord(
            termCode: '2025-2026-2',
            courseName: '线性代数',
            credit: 3,
            gpaPoints: 4.0,
            score: '90',
            courseCode: 'MATH101',
          ),
        ],
      },
    );

    await cache.write(SnapshotCache.grades, snap.toJson());
    final restored =
        await cache.readMapped(SnapshotCache.grades, GradesSnapshot.fromJson);
    expect(restored, isNotNull);
    expect(restored!.live, isTrue);
    expect(restored.records, hasLength(1));
    expect(restored.records.first.courseName, '线性代数');
    expect(restored.records.first.credit, 3.0);
    expect(restored.groupedByTerm['2025-2026-2'], hasLength(1));

    // clearAll removes grades key
    await cache.clearAll();
    expect(await cache.read(SnapshotCache.grades), isNull);
    expect(await cache.read(SnapshotCache.schedule), isNull);
  });

  test('AppStrings updatedAtLabel formats M月d日 HH:mm', () {
    final label = AppStrings.updatedAtLabel(DateTime(2026, 9, 14, 15, 5));
    expect(label, contains('9月14日'));
    expect(label, contains('15:05'));
    expect(AppStrings.cacheBanner(DateTime(2026, 9, 14, 8, 30)),
        contains('缓存数据'));
  });
}
