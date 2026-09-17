import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Build provenance exposed by the platform-specific application shell.
///
/// Android release builds populate these values from the Git checkout at build
/// time. Other platforms, and Android builds that cannot determine the value,
/// return [unknown] instead of guessing from the Dart source.
class BuildProvenance {
  const BuildProvenance({
    required this.commitSha,
    required this.branch,
    required this.dirty,
  });

  static const unknown = BuildProvenance(
    commitSha: 'unknown',
    branch: 'unknown',
    dirty: null,
  );

  static const MethodChannel _channel = MethodChannel('campus/build_provenance');

  final String commitSha;
  final String branch;
  final bool? dirty;

  static Future<BuildProvenance> load() async {
    if (defaultTargetPlatform != TargetPlatform.android) return unknown;
    try {
      final values = await _channel.invokeMethod<Map<Object?, Object?>>('get');
      if (values == null) return unknown;
      return BuildProvenance(
        commitSha: _stringValue(values['commitSha']),
        branch: _stringValue(values['branch']),
        dirty: _boolValue(values['dirty']),
      );
    } on PlatformException {
      return unknown;
    } on MissingPluginException {
      return unknown;
    }
  }

  static String _stringValue(Object? value) =>
      value is String && value.isNotEmpty ? value : 'unknown';

  static bool? _boolValue(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }
}
