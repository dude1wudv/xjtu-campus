import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/course.dart';
import '../domain/timetable_logic.dart';

Color courseColor(Course course) {
  const colors = [
    Color(0xFF305C92),
    Color(0xFF227A6B),
    Color(0xFF806139),
    Color(0xFF735A9D),
    Color(0xFFA35460),
  ];
  final hash = course.name.runes.fold(0, (v, c) => v + c);
  return colors[hash % colors.length];
}

class CourseTile extends StatelessWidget {
  const CourseTile({
    super.key,
    required this.course,
    required this.day,
    this.highlight = false,
  });
  final Course course;
  final DateTime day;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final color = courseColor(course);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(courseRoute(course, day)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 62,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 58,
                child: Column(
                  children: [
                    Text(
                      course.startOf(day).formatClock().split('–').first,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${course.startPeriod}–${course.endPeriod}节',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (highlight)
                      Text(
                        '正在上课',
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                    Text(
                      course.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${course.building} ${course.room}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
