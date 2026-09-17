import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../attendance/presentation/course_attendance_badge.dart';
import '../../calendar/domain/calendar_day_logic.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../../schedule/domain/course.dart';
import '../../homework/presentation/homework_widgets.dart';
import '../../campus_card/presentation/campus_card_providers.dart';
import 'campus_connection_card.dart';
import 'campus_services.dart';

class HomeDashboard extends ConsumerWidget {
  const HomeDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final snapshot = ref.watch(scheduleSnapshotProvider);
    final data = snapshot.asData?.value;
    final now = DateTime.now();
    final today = coursesOnDay(data?.courses ?? <Course>[], now, fallbackWeek: data?.week);
    final card = ref.watch(campusCardSnapshotProvider).asData?.value;
    return AppPageScaffold(
      appBar: AppBar(title: const Text('今天'), actions: [
        IconButton(tooltip: '校历', icon: const Icon(CupertinoIcons.calendar), onPressed: () => context.push('/calendar')),
        IconButton(tooltip: '账号', icon: const Icon(CupertinoIcons.person_crop_circle), onPressed: () => context.push('/login')),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.read(scheduleSnapshotProvider.notifier).refresh(force: true),
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
          physics: const AlwaysScrollableScrollPhysics(), children: [
          Text(DateFormat('M月d日 EEEE', 'zh_CN').format(now), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          GlassSurface(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(auth.isLoggedIn ? '你好，${auth.user.displayName}' : '开启你的校园一天',
                style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(data == null ? '正在整理你的课程安排' : '今日 ${today.length} 门课  ·  第 ${data.week} 周'),
              const SizedBox(height: 20),
              Wrap(spacing: 12, runSpacing: 8, children: [
                ActionChip(avatar: const Icon(CupertinoIcons.calendar, size: 18),
                  label: const Text('查看课表'), onPressed: () => context.go('/schedule')),
                ActionChip(avatar: const Icon(CupertinoIcons.creditcard, size: 18),
                  label: Text(card?.card == null ? '校园卡' : '余额 ¥${card!.card!.balanceLabel}${card.fromCache ? ' · 缓存' : ''}'),
                  onPressed: () => context.push('/campus-card')),
              ]),
            ],
          ))),
          const SizedBox(height: 16),
          const CampusConnectionCard(),
          const SizedBox(height: 24),
          Row(children: [Expanded(child: Text('日程', style: Theme.of(context).textTheme.titleLarge)),
            TextButton(onPressed: () => context.push('/calendar'), child: const Text('展开校历'))]),
          if (snapshot.isLoading) const LinearProgressIndicator(),
          if (data?.fromCache == true) const Text('课程来自缓存'),
          if (today.isEmpty) AppSurfaceCard(child: Text(data == null ? '课表尚未同步' : '今天没有已知课程，留点时间给自己。')),
          for (final course in today) AppSurfaceCard(margin: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
                color: const Color(0xFFE8F1FF), borderRadius: BorderRadius.circular(18)),
                child: Text('${course.startPeriod}–${course.endPeriod}', style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.w700))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.name, style: Theme.of(context).textTheme.titleMedium),
                Text(course.location), CourseAttendanceBadge(course: course, day: now),
              ])),
            ])),
          const HomeworkHomeCard(),
          const SizedBox(height: 24),
          Text('学习', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14), const CampusServiceGrid(services: CampusService.learning),
          const SizedBox(height: 24), Text('生活', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14), const CampusServiceGrid(services: CampusService.living),
        ]),
      ),
    );
  }
}
