import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/update/apk_updater.dart';
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
              leading: const Icon(Icons.school_outlined, color: AppColors.navy),
              title: const Text(AppStrings.academicsTitle),
              subtitle: const Text(AppStrings.academicsSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).maybePop();
                context.push('/academics');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined,
                  color: AppColors.navy),
              title: const Text(AppStrings.calendarTitle),
              subtitle: const Text(AppStrings.calendarHubSubtitle),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).maybePop();
                context.push('/calendar');
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.system_update_alt_rounded,
                  color: AppColors.navy),
              title: const Text('检查更新'),
              subtitle: const Text('应用内下载并安装（同包名同签名可覆盖保留数据）'),
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

/// Soft update prompt used by About + home auto-check.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  UpdateAvailable update, {
  bool barrierDismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
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
              const SizedBox(height: 8),
              const Text(
                '覆盖安装保留本地数据（同包名同签名）。',
                style: TextStyle(fontSize: 13, height: 1.35),
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
              if (!context.mounted) return;
              await downloadAndInstallUpdate(context, update);
            },
            child: const Text('下载并安装'),
          ),
        ],
      );
    },
  );
}

Future<void> downloadAndInstallUpdate(
  BuildContext context,
  UpdateAvailable update,
) async {
  final downloadUri = Uri.tryParse(update.downloadUrl);
  final looksLikeApk = downloadUri != null &&
      (update.downloadUrl.toLowerCase().contains('.apk') ||
          update.downloadUrl != update.htmlUrl);

  if (!looksLikeApk || !Platform.isAndroid) {
    await _openReleasePage(context, update.htmlUrl);
    return;
  }

  final cancelToken = CancelToken();
  final progress = ValueNotifier<double?>(0);
  var closed = false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在下载更新'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) {
              final pct = value == null
                  ? null
                  : (value.isNaN ? null : value.clamp(0.0, 1.0));
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: pct),
                  const SizedBox(height: 12),
                  Text(
                    pct == null
                        ? '连接中…'
                        : '已下载 ${(pct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '下载完成后将打开系统安装器。覆盖安装保留本地数据（同包名同签名）。',
                    style: TextStyle(fontSize: 12.5, height: 1.35),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelToken.cancel('user');
                if (!closed) {
                  closed = true;
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('取消'),
            ),
          ],
        ),
      );
    },
  ).whenComplete(() => closed = true);

  final updater = ApkUpdater();
  try {
    final file = await updater.download(
      url: update.downloadUrl,
      cancelToken: cancelToken,
      onProgress: (received, total) {
        if (total > 0) {
          progress.value = received / total;
        } else {
          progress.value = null;
        }
      },
    );

    if (context.mounted && !closed) {
      closed = true;
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;
    final ok = await updater.install(file);
    if (!ok && context.mounted) {
      await _offerReleaseFallback(context, update.htmlUrl);
    }
  } on DioException catch (e) {
    if (CancelToken.isCancel(e)) {
      // user cancelled
    } else if (context.mounted) {
      if (!closed) {
        closed = true;
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：${e.message ?? e.type.name}')),
      );
      await _offerReleaseFallback(context, update.htmlUrl);
    }
  } on Object catch (e) {
    if (context.mounted) {
      if (!closed) {
        closed = true;
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载或安装失败：$e')),
      );
      await _offerReleaseFallback(context, update.htmlUrl);
    }
  } finally {
    progress.dispose();
  }
}

Future<void> _offerReleaseFallback(BuildContext context, String htmlUrl) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('无法打开安装器'),
      content: const Text(
        '可前往 GitHub Release 页面手动下载安装。覆盖安装保留本地数据（同包名同签名）。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('打开发布页'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await _openReleasePage(context, htmlUrl);
  }
}

Future<void> _openReleasePage(BuildContext context, String htmlUrl) async {
  final uri = Uri.tryParse(htmlUrl);
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开发布页')),
    );
  }
}

/// Session-scoped auto-check (once per cold start / process).
class HomeUpdateAutoCheck {
  HomeUpdateAutoCheck._();

  static var _ranThisSession = false;

  /// Call after first frame on home. Soft dialog only when newer.
  static Future<void> runOnce(BuildContext context) async {
    if (_ranThisSession) return;
    _ranThisSession = true;
    if (!context.mounted) return;

    final checker = UpdateChecker();
    try {
      final result = await checker.check();
      if (!context.mounted) return;
      if (result is UpdateAvailable) {
        await showUpdateAvailableDialog(context, result);
      }
    } finally {
      checker.close();
    }
  }

  /// Test hook.
  @visibleForTesting
  static void resetForTest() => _ranThisSession = false;
}
