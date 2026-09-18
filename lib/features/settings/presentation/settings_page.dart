import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/campus_platform.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/app_surface_card.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../about/presentation/about_sheet.dart';
import 'settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final running = ref.watch(backgroundRunningProvider);
    final user = ref.watch(authControllerProvider).user;
    return AppPageScaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 112),
        children: [
          AppSurfaceCard(
            onTap: () => context.push('/login'),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.person_crop_circle_fill,
                  size: 44,
                  color: Color(0xFF007AFF),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.isGuest ? '登录校园账号' : user.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text('账号与校园认证'),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('外观与操作'),
          const SizedBox(height: 10),
          AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  title: const Text('液态玻璃效果'),
                  subtitle: const Text('关闭后使用清晰的实色面板，减少图形开销'),
                  value: settings.glass,
                  onChanged: settings.loaded
                      ? (v) =>
                            ref.read(settingsProvider.notifier).save(glass: v)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('桌面与后台'),
          const SizedBox(height: 10),
          AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  title: const Text('桌面小组件显示个人信息'),
                  subtitle: const Text('在桌面显示课程、考勤、作业、余额和预约摘要。其他能查看桌面的人也能看到。'),
                  value: settings.widgets,
                  onChanged:
                      (!kIsWeb &&
                              defaultTargetPlatform ==
                                  TargetPlatform.android) &&
                          settings.loaded
                      ? (v) =>
                            ref.read(settingsProvider.notifier).save(widgets: v)
                      : null,
                ),
                ListTile(
                  title: const Text('添加「校园一周」小组件'),
                  trailing: const Icon(CupertinoIcons.add_circled),
                  onTap:
                      (!kIsWeb &&
                          defaultTargetPlatform == TargetPlatform.android)
                      ? () async {
                          try {
                            final pinned =
                                await campusPlatform.invokeMethod<bool>(
                                  'pinWidget',
                                ) ??
                                false;
                            if (!pinned) _message('请长按桌面，在小组件列表中选择「校园一周」');
                          } catch (_) {
                            _message('请通过桌面的小组件列表添加');
                          }
                        }
                      : null,
                ),
                SwitchListTile.adaptive(
                  title: const Text('保持后台刷新'),
                  subtitle: const Text(
                    '本次运行中约每 15 分钟刷新，显示常驻通知。可能增加耗电和流量；系统限制、强制停止或认证过期会中断。',
                  ),
                  value: running,
                  onChanged:
                      !(!kIsWeb &&
                              defaultTargetPlatform ==
                                  TargetPlatform.android) ||
                          _busy ||
                          user.isGuest ||
                          user.isDemo
                      ? null
                      : (v) async {
                          setState(() => _busy = true);
                          try {
                            final enabled = await ref
                                .read(backgroundRunningProvider.notifier)
                                .toggle(v);
                            if (v && !enabled) _message('未能开启，请允许通知权限后重试');
                          } catch (_) {
                            _message('系统暂不允许后台刷新，请稍后重试');
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('关于与服务'),
          const SizedBox(height: 10),
          AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  title: const Text('用户协议与隐私说明'),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: () => context.push('/agreement'),
                ),
                ListTile(
                  title: const Text('课程闹钟'),
                  trailing: const Icon(CupertinoIcons.alarm),
                  onTap: () => context.push('/alarms'),
                ),
                ListTile(
                  title: const Text('检查更新与版本'),
                  trailing: const Icon(CupertinoIcons.arrow_down_circle),
                  onTap: () => showAboutSheet(context),
                ),
                const ListTile(
                  title: Text('交大校园助手'),
                  subtitle: Text('独立开发的校园工具，非学校官方客户端'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const agreementText = '''欢迎使用交大校园助手
版本：2026-09-17

1. 服务范围
本软件是独立开发的校园信息工具，并非学校官方客户端。课程、考勤、作业、余额、预约等信息以学校系统最终记录为准。缓存内容可能过期，重要操作请在官方系统核对。

2. 账号与操作
请仅登录本人有权使用的账号，遵守学校服务的使用规定。预约、取消预约及在学校网页提交作业等操作由你自行决定。软件不承诺抢到座位，也不会因缺少考勤记录自动判定缺勤。

3. 数据处理
软件会访问学校服务，以读取你请求的个人信息。登录凭据保存在设备安全存储中，不长期保存学校密码；部分业务数据缓存在本机。访问学校页面时也适用对应网站的隐私规则。本功能不向新增的第三方分析服务发送校园数据。

4. 桌面与后台
桌面信息默认关闭。开启后，桌面小组件会显示个人摘要，旁人可能看到。可以在设置中关闭显示或移除小组件。后台刷新默认关闭，开启后会使用网络、电量并显示通知；系统可能限制运行时间，软件无法保证永久常驻或实时更新。

5. 数据控制与退出
可以在账号页面退出登录，停止后台刷新，并清除当前桌面摘要。卸载软件会删除应用本地数据；学校系统中的记录不会因此删除。使用前请确认你接受上述说明。如不同意，可以退出并停止使用。

6. 问题反馈
请通过项目仓库 dude1wudv/xjtu-campus 的 Issues 反馈问题。不要公开学号、密码、Cookie、令牌或包含个人信息的完整日志。''';

class AgreementPage extends ConsumerWidget {
  const AgreementPage({super.key, this.acceptMode = false});
  final bool acceptMode;
  @override
  Widget build(BuildContext context, WidgetRef ref) => AppPageScaffold(
    appBar: AppBar(
      title: const Text('用户协议与隐私说明'),
      automaticallyImplyLeading: !acceptMode,
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: const [SelectableText(agreementText)],
    ),
    bottomNavigationBar: !acceptMode
        ? null
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    if (kIsWeb) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('可关闭此标签页以退出')),
                      );
                    } else {
                      SystemNavigator.pop();
                    }
                  },
                  child: const Text('不同意并退出'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .save(agreement: true),
                    child: const Text('同意并继续'),
                  ),
                ),
              ],
            ),
          ),
  );
}

class AgreementGate extends ConsumerWidget {
  const AgreementGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (!settings.loaded)
      return const Material(child: Center(child: CircularProgressIndicator()));
    return settings.agreement ? child : const AgreementPage(acceptMode: true);
  }
}
