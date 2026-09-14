import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_constants.dart';
import '../logging/app_logger.dart';

/// GitHub Releases 检查结果。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.htmlUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String downloadUrl;
  final String htmlUrl;
}

class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate({required this.currentVersion});

  final String currentVersion;
}

class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.message);

  final String message;
}

/// 对照 GitHub Releases API 检查是否有新版本。
class UpdateChecker {
  UpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<UpdateCheckResult> check({PackageInfo? packageInfo}) async {
    try {
      final info = packageInfo ?? await PackageInfo.fromPlatform();
      final current = info.version.trim();

      final uri = Uri.parse(AppConstants.githubReleasesApi);
      final response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'xjtu-campus-update-checker',
        },
      );

      if (response.statusCode == 404) {
        return const UpdateCheckFailed('尚未发布正式版本');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warn(
          'UpdateChecker HTTP ${response.statusCode}: ${response.body}',
        );
        return UpdateCheckFailed('检查更新失败（HTTP ${response.statusCode}）');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const UpdateCheckFailed('发布信息格式异常');
      }

      final tagName = (decoded['tag_name'] as String?)?.trim() ?? '';
      if (tagName.isEmpty) {
        return const UpdateCheckFailed('发布信息缺少版本号');
      }

      final latest = normalizeVersion(tagName);
      final currentNorm = normalizeVersion(current);
      if (compareSemver(latest, currentNorm) <= 0) {
        return UpdateUpToDate(currentVersion: currentNorm);
      }

      final assets = decoded['assets'];
      final apkUrl = pickApkDownloadUrl(assets is List ? assets : null);

      final htmlUrl = (decoded['html_url'] as String?)?.trim() ??
          AppConstants.githubRepoUrl;
      final name = (decoded['name'] as String?)?.trim();
      final body = (decoded['body'] as String?)?.trim() ?? '';

      return UpdateAvailable(
        currentVersion: currentNorm,
        latestVersion: latest,
        releaseName: (name != null && name.isNotEmpty) ? name : tagName,
        releaseNotes: body,
        downloadUrl: apkUrl ?? htmlUrl,
        htmlUrl: htmlUrl,
      );
    } on Object catch (error, stack) {
      AppLogger.warn('UpdateChecker 失败: $error\n$stack');
      return const UpdateCheckFailed('网络异常，暂时无法检查更新');
    }
  }


  /// Prefer `xjtu-campus-arm64-release.apk`, else first `.apk` asset URL.
  static String? pickApkDownloadUrl(List<dynamic>? assets) {
    if (assets == null) return null;
    String? preferred;
    String? first;
    for (final raw in assets) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String?)?.toLowerCase() ?? '';
      final url = raw['browser_download_url'] as String?;
      if (!name.endsWith('.apk') || url == null || url.isEmpty) continue;
      first ??= url;
      if (name == 'xjtu-campus-arm64-release.apk') {
        preferred = url;
      }
    }
    return preferred ?? first;
  }

  void close() => _client.close();

  /// 去掉前导 `v` / `V`，只保留数字段。
  static String normalizeVersion(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    return s.trim();
  }

  /// 比较两个 semver（如 `1.0.1`）。返回正数表示 [a] 更新。
  static int compareSemver(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final av = i < pa.length ? pa[i] : 0;
      final bv = i < pb.length ? pb[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _parts(String version) {
    return [
      for (final p in normalizeVersion(version).split('.'))
        int.tryParse(p) ?? 0,
    ];
  }
}
