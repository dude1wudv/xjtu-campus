import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/platform/build_provenance.dart';
import '../data/attendance_diagnostics.dart';

Future<void> showAttendanceDiagnostics(BuildContext context) async {
  final provenance = await BuildProvenance.load();
  String version = 'unknown', buildNumber = 'unknown';
  try {
    final info = await PackageInfo.fromPlatform();
    version = info.version;
    buildNumber = info.buildNumber;
  } catch (_) { /* Missing package metadata is not evidence of an old APK. */ }
  AttendanceDiagnostics.build = {
    'version': version, 'buildNumber': buildNumber,
    'commitSha': provenance.commitSha, 'branch': provenance.branch,
    'dirty': provenance.dirty,
  };
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
  context: context, isScrollControlled: true, builder: (context) => SafeArea(
    child: SizedBox(height: MediaQuery.sizeOf(context).height * .75,
      child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        const Text('考勤接口诊断', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('包含安装包来源、脚本/桥接状态、脱敏路径及请求/响应字段类型；不包含密码、令牌或个人考勤内容。'),
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
}
