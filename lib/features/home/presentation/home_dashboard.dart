import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_page_scaffold.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../campus_card/presentation/campus_card_providers.dart';
import '../../tasks/presentation/tasks_page.dart';
import '../../tasks/presentation/task_providers.dart';
import '../../schedule/domain/timetable_logic.dart';
import '../../schedule/presentation/course_tile.dart';
import '../../schedule/presentation/schedule_providers.dart';
import '../../schedule/presentation/schedule_status.dart';
import '../../schedule/presentation/schedule_transfer.dart';
import 'campus_services.dart';

class HomeDashboard extends ConsumerStatefulWidget {
  const HomeDashboard({super.key});
  @override
  ConsumerState<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends ConsumerState<HomeDashboard> {
  Timer? timer;
  bool refreshing = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    final auth = ref.read(authControllerProvider);
    Future<void> safe(Future<Object?> task) async {
      try {
        await task;
      } catch (_) {}
    }

    final tasks = <Future<void>>[safe(refreshTaskSources(ref))];
    if (!kIsWeb && auth.isLoggedIn && !auth.user.isDemo) {
      tasks.add(safe(ref.read(campusCardSnapshotProvider.notifier).refresh()));
    }
    await Future.wait(tasks);
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final value = ref.watch(scheduleSnapshotProvider);
    final data = value.asData?.value;
    final now = DateTime.now();
    final courses = data == null ? null : coursesForDay(data, now, now);
    final remaining = courses?.where((c) => c.endAt(now).isAfter(now)).toList();
    final next = remaining == null || remaining.isEmpty
        ? null
        : remaining.first;
    final actual = !kIsWeb && auth.isLoggedIn && !auth.user.isDemo;
    final cardValue = actual ? ref.watch(campusCardSnapshotProvider) : null;
    final card = cardValue?.asData?.value;
    final available =
        data != null &&
        (data.failure == null || data.fromCache) &&
        (!data.currentWeekOnly ||
            mondayOf(now) ==
                mondayOf(data.sourceMonday ?? data.cachedAt ?? now));
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text('交大 · 今天'),
        actions: [
          IconButton(
            tooltip: '刷新首页',
            onPressed: refreshing ? null : refresh,
            icon: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '账号',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/login'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
          children: [
            Row(
              children: [
                const Icon(Icons.school_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'XI’AN JIAOTONG UNIVERSITY',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(letterSpacing: 1.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${now.hour < 12
                  ? '上午好'
                  : now.hour < 18
                  ? '下午好'
                  : '晚上好'}${auth.isLoggedIn ? '，${auth.user.displayName}' : '，交大同学'}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${DateFormat('M月d日 EEEE', 'zh_CN').format(now)}  ·  把校园的一天，安排得刚刚好。',
            ),
            const SizedBox(height: 24),
            ScheduleStatus(value: value),
            const SizedBox(height: 16),
            const TodayTaskSummary(),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, size) {
                final main = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF234D60),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            next != null && !next.startAt(now).isAfter(now)
                                ? '正在进行'
                                : '接下来',
                            style: const TextStyle(
                              color: Color(0xFFBFD7DF),
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            next?.name ?? (available ? '给自己一段自由时间' : '等待课表同步'),
                            style: const TextStyle(
                              fontSize: 26,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            next == null
                                ? (available
                                      ? '今天没有更多已知课程，去看看一周的安排吧。'
                                      : '同步后，这里会展示你的下一节课。')
                                : '${next.periodLabelFor(now)}\n${next.location}',
                            style: const TextStyle(
                              color: Color(0xFFDBE7EB),
                              height: 1.8,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.tonal(
                            onPressed: () => next == null
                                ? context.go('/schedule')
                                : context.push(courseRoute(next, now)),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                            child: Text(next == null ? '查看一周课表' : '查看课程详情'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '今日日程',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          available ? '${courses!.length} 门课程' : '尚未同步',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (value.isLoading && data == null)
                      const ScheduleSkeleton()
                    else if (available && courses!.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('今天没有已知课程。祝你拥有充实的一天。'),
                        ),
                      )
                    else if (available)
                      for (final c in courses!)
                        CourseTile(
                          course: c,
                          day: now,
                          highlight:
                              !c.startAt(now).isAfter(now) &&
                              c.endAt(now).isAfter(now),
                        ),
                  ],
                );
                final side = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.event_note_outlined, size: 26),
                            const SizedBox(height: 12),
                            Text(
                              '这一周，心中有数',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              available
                                  ? '第 ${teachingWeek(data, now, now)} 教学周 · ${data.courses.where((c) => c.weeks.isEmpty || c.weeks.contains(teachingWeek(data, now, now))).length} 次课程安排'
                                  : '同步课程后查看本周安排',
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => context.go('/schedule'),
                              child: const Text('打开周课表'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (kIsWeb)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '把课表带到电脑上',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                '在客户端课表页导出 JSON，再粘贴到这里。课程详情与笔记也能在浏览器使用。',
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () =>
                                    showScheduleTransfer(context, ref, data),
                                child: const Text('导入个人课表'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (actual)
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(20),
                          leading: const Icon(Icons.credit_card),
                          title: const Text('校园卡'),
                          subtitle: Text(
                            cardValue!.isLoading
                                ? '正在同步余额'
                                : cardValue.hasError || card?.card == null
                                ? '余额未同步，点击重试'
                                : '¥${card!.card!.balanceLabel}${card.fromCache ? ' · 上次查询' : ''}',
                          ),
                          onTap: () => context.push('/campus-card'),
                        ),
                      ),
                  ],
                );
                if (size.maxWidth < 850)
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [main, const SizedBox(height: 24), side],
                  );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: main),
                    const SizedBox(width: 28),
                    Expanded(flex: 4, child: side),
                  ],
                );
              },
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 32),
              Text('校园服务', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const CampusServiceGrid(
                services: [...CampusService.learning, ...CampusService.living],
              ),
            ],
            const SizedBox(height: 28),
            Text(
              '饮水思源 · 爱国荣校\n独立开发的校园工具，非学校官方客户端',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
