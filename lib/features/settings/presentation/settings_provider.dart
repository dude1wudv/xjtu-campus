import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({this.loaded = false, this.glass = true,
    this.widgets = false, this.agreement = false});
  final bool loaded, glass, widgets, agreement;
}
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!ref.mounted) return;
      state = AppSettings(loaded: true, glass: prefs.getBool('ui.glass') ?? true,
        widgets: prefs.getBool('desktop.enabled') ?? false,
        agreement: prefs.getBool('agreement.v1') ?? false);
    });
    return const AppSettings();
  }
  Future<void> save({bool? glass, bool? widgets, bool? agreement}) async {
    final prefs = await SharedPreferences.getInstance();
    if (glass != null) await prefs.setBool('ui.glass', glass);
    if (widgets != null) await prefs.setBool('desktop.enabled', widgets);
    if (agreement != null) await prefs.setBool('agreement.v1', agreement);
    if (!ref.mounted) return;
    state = AppSettings(loaded: true, glass: glass ?? state.glass,
      widgets: widgets ?? state.widgets, agreement: agreement ?? state.agreement);
  }
}
final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
