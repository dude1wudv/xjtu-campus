import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:xjtu_campus/app.dart';
import 'package:xjtu_campus/core/di/core_providers.dart';
import 'package:xjtu_campus/core/l10n/app_strings.dart';
import 'package:xjtu_campus/core/storage/memory_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
      ],
      child: const CampusApp(),
    );
  }

  testWidgets('首页以中文底部导航启动并展示模拟课表入口', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(AppStrings.appName), findsWidgets);
    expect(find.text(AppStrings.navSchedule), findsWidgets);
    expect(find.text(AppStrings.navClassroom), findsWidgets);
    expect(find.text(AppStrings.navNotices), findsWidgets);
    expect(find.text(AppStrings.navAlarms), findsWidgets);
    expect(find.text(AppStrings.mockBanner), findsWidgets);
  });

  testWidgets('登录页提供统一认证与演示两条路径', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip(AppStrings.openLogin));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.loginAction), findsOneWidget);
    expect(find.text(AppStrings.loginDemo), findsOneWidget);
    expect(find.text(AppStrings.loginTitle), findsWidgets);
  });

  testWidgets('闹钟页展示一键创建按钮与建议起床时间', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text(AppStrings.navAlarms));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(AppStrings.createAlarms), findsWidgets);
    expect(find.text(AppStrings.alarmsTitle), findsWidgets);
    expect(find.textContaining(AppStrings.wakeOffsetLabel), findsOneWidget);
  });
}
