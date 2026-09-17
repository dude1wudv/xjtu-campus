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
        child: GlassSurface(shadow: false, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Stack(children: [
            // Move one constant-color indicator. Fading separate containers
            // from Colors.transparent (transparent black) to white makes both
            // the outgoing and incoming tabs pass through a dark gray tint.
            Positioned.fill(child: IgnorePointer(child: AnimatedAlign(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + 2 * widget.navigationShell.currentIndex / (_tabs.length - 1), 0),
              child: FractionallySizedBox(widthFactor: 1 / _tabs.length, heightFactor: 1,
                child: DecoratedBox(decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.white.withValues(alpha: .85),
                )),
              ),
            ))),
            RepaintBoundary(child: Row(children: [
              for (var i = 0; i < _tabs.length; i++) Expanded(
                child: _TabButton(
                  label: _tabs[i].$1, icon: _tabs[i].$2,
                  selected: widget.navigationShell.currentIndex == i,
                  onTap: () {
                    _lastBack = null;
                    if (widget.navigationShell.currentIndex != i) {
                      widget.navigationShell.goBranch(i);
                    }
                  },
                ),
              ),
            ])),
          ]),
        )),
      ),
    ),
  );
}


/// No Material ink overlay: keyboard and accessibility activation use the same
/// callback as touch, without drawing a second highlight on either tab.
class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.icon,
    required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF007AFF) : const Color(0xFF747A87);
    return Semantics(button: true, selected: selected, label: label, onTap: onTap,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          onTap(); return null;
        })},
        child: GestureDetector(behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true, onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: ExcludeSemantics(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: color, shadows: const []),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color,
                shadows: const [], fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ])),
          ),
        ),
      ),
    );
  }
}
