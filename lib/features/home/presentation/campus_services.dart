import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_surface_card.dart';

/// One catalog keeps home and the academic hub in the same order and style.
class CampusService {
  const CampusService(this.title, this.subtitle, this.icon, this.route,
      {this.isTab = false});

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final bool isTab;

  static const learning = [
    CampusService('作业中心', '思源学堂 · 截止日期', Icons.assignment_outlined, '/homework'),
    CampusService('考勤查询', '课程考勤 · 状态明细', Icons.fact_check_outlined, '/attendance'),
    CampusService('课程表', '每日安排 · 每周课表', Icons.calendar_view_week_outlined,
        '/schedule', isTab: true),
    CampusService('成绩查询', '学期成绩 · 学分绩点', Icons.grade_outlined, '/grades'),
    CampusService('考试安排', '考试时间 · 考场信息', Icons.edit_calendar_outlined, '/exams'),
    CampusService('校历', '教学周 · 学期安排', Icons.calendar_month_outlined, '/calendar'),
  ];

  static const living = [
    CampusService('空闲教室', '寻找一处自习空间', Icons.meeting_room_outlined,
        '/classroom', isTab: true),
    CampusService('图书馆座位', '查询座位 · 预约自习', Icons.event_seat_outlined,
        '/library-seats'),
    CampusService('校园卡', '余额查询 · 消费记录', Icons.credit_card_outlined,
        '/campus-card'),
    CampusService('课程闹钟', '课前提醒 · 起床闹钟', Icons.alarm_outlined,
        '/alarms', isTab: true),
  ];
}

class CampusServiceGrid extends StatelessWidget {
  const CampusServiceGrid({super.key, required this.services});

  final List<CampusService> services;

  @override
  Widget build(BuildContext context) {
    // Natural tile height accommodates accessibility text without fixed ratios.
    return LayoutBuilder(builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
      final columns = constraints.maxWidth < 300 || largeText
          ? 1
          : constraints.maxWidth >= 640 ? 4 : 2;
      final width = (constraints.maxWidth -
              AppTokens.spaceMd * (columns - 1)) / columns;
      return Wrap(
        spacing: AppTokens.spaceMd,
        runSpacing: AppTokens.spaceMd,
        children: [
          for (final service in services)
            SizedBox(
              width: width,
              child: AppSurfaceCard(
                onTap: () {
                  if (service.isTab) {
                    context.go(service.route);
                  } else {
                    context.push(service.route);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.chip,
                        borderRadius: AppTokens.borderSm,
                      ),
                      child: Icon(service.icon, size: 22, color: AppColors.navy),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    Text(service.title,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Text(service.subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}
