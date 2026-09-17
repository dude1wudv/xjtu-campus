import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_page_scaffold.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../home/presentation/campus_services.dart';

/// A navigation-only hub: repositories load when the destination opens.
class AcademicsPage extends StatelessWidget {
  const AcademicsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: AppBar(
        title: const Text(AppStrings.academicsTitle),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: AppTokens.pagePadding,
        children: const [
          AppSectionHeader(title: '学习教务', subtitle: '把每一天的学习安排得井井有条'),
          CampusServiceGrid(services: CampusService.learning),
          AppSectionHeader(title: '校园生活', subtitle: '常用校园服务'),
          CampusServiceGrid(services: CampusService.living),
        ],
      ),
    );
  }
}
