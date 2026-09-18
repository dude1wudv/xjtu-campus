import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xjtu_campus/app.dart';
import 'package:xjtu_campus/core/di/core_providers.dart';
import 'package:xjtu_campus/core/l10n/app_strings.dart';
import 'package:xjtu_campus/core/storage/memory_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'agreement.v1': true});
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
      ],
      child: const CampusApp(),
    );
  }

  Future<void> pumpSettled(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    // settingsProvider loads SharedPreferences on a microtask
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  testWidgets('首页以中文底部导航启动', (tester) async {
    await pumpSettled(tester);

    expect(find.text('今天'), findsWidgets);
    expect(find.text('课表'), findsWidgets);
    expect(find.text('自习'), findsWidgets);
    expect(find.text('通知'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('设置页可进入统一认证与演示登录', (tester) async {
    await pumpSettled(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('登录校园账号'));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.loginAction), findsOneWidget);
    expect(find.text(AppStrings.loginDemo), findsOneWidget);
    expect(find.text(AppStrings.loginTitle), findsWidgets);

    await tester.tap(find.text(AppStrings.loginDemo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('同学 demo'), findsWidgets);
  });

  testWidgets('设置页提供课程闹钟入口', (tester) async {
    await pumpSettled(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('登录校园账号'), findsWidgets);
    final alarms = find.text('课程闹钟');
    await tester.scrollUntilVisible(
      alarms,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(alarms, findsOneWidget);
  });
}
