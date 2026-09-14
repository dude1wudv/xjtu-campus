import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/update_checker.dart';

/// 首页「关于」底栏：检查更新 / 打开 GitHub。
Future<void> showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => const _AboutSheetBody(),
  );
}

class _AboutSheetBody extends StatefulWidget {
  const _AboutSheetBody();

  @override
  State<_AboutSheetBody> createState() => _AboutSheetBodyState();
}

class _AboutSheetBodyState extends State<_AboutSheetBody> {
  String _versionLabel = '…';
  var _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = '${info.version}+${info.buildNumber}';
      });
    } on Object {
      if (!mounted) return;
      setState(() => _versionLabel = '未知');
    }
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse(AppConstants.githubRepoUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开 GitHub 链接')),
      );
    }
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final checker = UpdateChecker();
    try {
      final result = await checker.check();
      if (!mounted) return;
      switch (result) {
        case UpdateUpToDate():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已是最新版本')),
          );
          Navigator.of(context).maybePop();
        case UpdateCheckFailed(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        case UpdateAvailable():
          Navigator.of(context).maybePop();
          if (!mounted) return;
          await showUpdateAvailableDialog(context, result);
      }
    } finally {
      checker.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '关于 ${AppStrings.appName}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '当前版本 $_versionLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update_alt_rounded,
                  color: AppColors.navy),
              title: const Text('检查更新'),
              subtitle: const Text('对照 GitHub Releases'),
              trailing: _checking
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checking ? null : _checkUpdate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code_rounded, color: AppColors.navy),
              title: const Text('打开 GitHub 仓库'),
              subtitle: Text(AppConstants.githubRepoUrl),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: _openGithub,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showUpdateAvailableDialog(
  BuildContext context,
  UpdateAvailable update,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('发现新版本 ${update.latestVersion}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                update.releaseName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '当前版本 ${update.currentVersion}',
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 13),
              ),
              if (update.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  update.releaseNotes,
                  style: const TextStyle(height: 1.4, fontSize: 13.5),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final uri = Uri.tryParse(update.downloadUrl);
              if (uri == null) return;
              final ok =
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('无法打开下载链接')),
                );
              }
            },
            child: const Text('下载更新'),
          ),
        ],
      );
    },
  );
}
