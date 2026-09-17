import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/glass_surface.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;
  @override
  State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  DateTime? _lastBack;
  static const _tabs = [
    ('今天', CupertinoIcons.square_grid_2x2_fill),
    ('课表', CupertinoIcons.calendar),
    ('自习', CupertinoIcons.book),
    ('通知', CupertinoIcons.bell),
    ('设置', CupertinoIcons.gear_alt),
  ];
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;
      final now = DateTime.now();
      if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
        SystemNavigator.pop();
      } else {
        _lastBack = now;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('再按一次返回键退出'), duration: Duration(seconds: 2)));
      }
    },
    child: Scaffold(
      extendBody: true,
      body: widget.navigationShell,
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom > 0 ? null : SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: GlassSurface(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(children: [for (var i = 0; i < _tabs.length; i++) Expanded(
            child: Semantics(selected: widget.navigationShell.currentIndex == i,
              child: InkWell(borderRadius: BorderRadius.circular(22), onTap: () {
                _lastBack = null;
                widget.navigationShell.goBranch(i);
              }, child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
                  color: widget.navigationShell.currentIndex == i ? Colors.white.withValues(alpha: .85) : Colors.transparent),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_tabs[i].$2, size: 22, color: widget.navigationShell.currentIndex == i
                      ? const Color(0xFF007AFF) : const Color(0xFF747A87)),
                  const SizedBox(height: 4),
                  Text(_tabs[i].$1, style: TextStyle(fontSize: 11,
                    fontWeight: widget.navigationShell.currentIndex == i ? FontWeight.w700 : FontWeight.w500)),
                ]),
              )),
            ),
          )]),
        )),
      ),
    ),
  );
}
