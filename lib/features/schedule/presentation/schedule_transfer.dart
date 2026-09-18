import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_schedule_store.dart';
import '../domain/schedule_repository.dart';
import 'schedule_providers.dart';

Future<void> showScheduleTransfer(
  BuildContext context,
  WidgetRef ref,
  ScheduleSnapshot? data,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _TransferDialog(data: data),
  );
  if (result == null) return;
  if (result == 'clear') await LocalScheduleStore.clear();
  ref.invalidate(scheduleSnapshotProvider);
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({this.data});
  final ScheduleSnapshot? data;
  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final controller = TextEditingController();
  String? error;
  bool saving = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(kIsWeb ? '导入与导出课表' : '导出到网页端'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('仅包含课程信息，不包含学号、密码或登录凭据。复制内容后，可在网页端粘贴导入。'),
            if (widget.data != null)
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制当前课表 JSON'),
                onPressed: () async {
                  try {
                    await Clipboard.setData(
                      ClipboardData(
                        text: LocalScheduleStore.encode(widget.data!),
                      ),
                    );
                    if (context.mounted)
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('课表已复制')));
                  } catch (_) {
                    if (mounted) setState(() => error = '浏览器未允许复制，请检查剪贴板权限');
                  }
                },
              ),
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 9,
                decoration: InputDecoration(
                  labelText: '粘贴课表 JSON',
                  errorText: error,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              const Text('导入会替换当前浏览器的本地课表。学校变更不会自动同步。'),
            ] else if (error != null)
              Text(error!),
          ],
        ),
      ),
    ),
    actions: [
      if (kIsWeb && widget.data?.imported == true)
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, 'clear'),
          child: const Text('清除本地课表'),
        ),
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (kIsWeb)
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  setState(() {
                    saving = true;
                    error = null;
                  });
                  try {
                    await LocalScheduleStore.save(controller.text);
                    if (context.mounted) Navigator.pop(context, 'imported');
                  } catch (_) {
                    if (mounted)
                      setState(() {
                        error = '导入失败，请检查 JSON 格式、星期和节次，以及浏览器存储权限';
                        saving = false;
                      });
                  }
                },
          child: Text(saving ? '正在导入' : '导入课表'),
        ),
    ],
  );
}
