import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/attendance_diagnostics.dart';

Future<void> showAttendanceDiagnostics(BuildContext context) => showModalBottomSheet<void>(
  context: context, isScrollControlled: true, builder: (context) => SafeArea(
    child: SizedBox(height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Text('考勤接口诊断', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('仅包含请求路径、状态码和字段类型，不包含账号、密码、令牌或考勤内容。复制后可用于反馈。'),
        const SizedBox(height: 12),
        Expanded(child: ValueListenableBuilder<int>(valueListenable: AttendanceDiagnostics.revision,
          builder: (_, value, child) => SingleChildScrollView(child: SelectableText(AttendanceDiagnostics.export(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11))))),
        Row(children: [TextButton(onPressed: AttendanceDiagnostics.clear, child: const Text('清空')),
          const Spacer(), FilledButton(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: AttendanceDiagnostics.export()));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制脱敏诊断')));
          }, child: const Text('复制诊断'))]),
      ])),
    ),
  ),
);
