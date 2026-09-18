import 'package:flutter/foundation.dart';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../logging/app_logger.dart';

/// Downloads an APK and hands it to the Android package installer via FileProvider.
class ApkUpdater {
  ApkUpdater({Dio? dio}) : _dio = dio ?? Dio();

  static const MethodChannel _channel = MethodChannel(
    'cn.edu.xjtu.xjtu_campus/apk_installer',
  );

  static const preferredApkName = 'xjtu-campus-arm64-release.apk';

  final Dio _dio;

  /// Download [url] into app support/cache. Reports byte progress via [onProgress].
  Future<File> download({
    required String url,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final updates = Directory('${dir.path}/updates');
    if (!await updates.exists()) {
      await updates.create(recursive: true);
    }
    final file = File('${updates.path}/$preferredApkName');
    if (await file.exists()) {
      try {
        await file.delete();
      } on Object {
        // overwrite via dio anyway
      }
    }

    AppLogger.info('ApkUpdater downloading $url → ${file.path}');
    await _dio.download(
      url,
      file.path,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        headers: const {
          'Accept': 'application/octet-stream',
          'User-Agent': 'xjtu-campus-updater',
        },
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 2),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );

    if (!await file.exists() || await file.length() < 1024) {
      throw StateError('APK 下载不完整');
    }
    return file;
  }

  Future<bool> canRequestPackageInstalls() async {
    if (!(!kIsWeb && defaultTargetPlatform == TargetPlatform.android))
      return false;
    try {
      final ok = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return ok ?? false;
    } on PlatformException catch (e) {
      AppLogger.warn('canRequestPackageInstalls: $e');
      return false;
    }
  }

  Future<void> openUnknownAppSourcesSettings() async {
    if (!(!kIsWeb && defaultTargetPlatform == TargetPlatform.android)) return;
    try {
      await _channel.invokeMethod<bool>('openUnknownAppSourcesSettings');
    } on PlatformException catch (e) {
      AppLogger.warn('openUnknownAppSourcesSettings: $e');
    }
  }

  /// Opens the system installer for [file]. Returns false if the intent failed.
  Future<bool> install(File file) async {
    if (!(!kIsWeb && defaultTargetPlatform == TargetPlatform.android))
      return false;
    try {
      final allowed = await canRequestPackageInstalls();
      if (!allowed) {
        await openUnknownAppSourcesSettings();
        // User may grant and retry; still attempt install so OEM flows work.
      }
      final ok = await _channel.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': file.path},
      );
      return ok ?? false;
    } on PlatformException catch (e) {
      AppLogger.warn('installApk failed: $e');
      return false;
    }
  }
}
