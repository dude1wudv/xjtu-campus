import 'dart:async';

import 'package:dio/dio.dart';

enum DataSource { none, live, cache, demo, local }

enum DataPhase { loading, ready, failed }

enum DataProblem {
  loginRequired,
  network,
  timeout,
  format,
  unavailable,
  partial,
  storage,
}

/// Source and synchronization outcome are independent: cached data can remain
/// available after a failed refresh. No raw server error is shown to users.
class DataStatus {
  const DataStatus({
    required this.phase,
    this.source = DataSource.none,
    this.problem,
    this.updatedAt,
  });
  const DataStatus.loading({this.source = DataSource.none, this.updatedAt})
    : phase = DataPhase.loading,
      problem = null;
  final DataPhase phase;
  final DataSource source;
  final DataProblem? problem;
  final DateTime? updatedAt;
  bool get hasData => source != DataSource.none;
  bool get needsLogin => problem == DataProblem.loginRequired;
  bool get isBusy => phase == DataPhase.loading;
  String get sourceLabel => switch (source) {
    DataSource.none => '尚无数据',
    DataSource.live => '学校数据',
    DataSource.cache => '缓存',
    DataSource.demo => '演示',
    DataSource.local => '本地',
  };
  String get title {
    if (needsLogin) return '需要重新认证';
    if (problem == DataProblem.partial) return '部分数据未同步';
    if (problem == DataProblem.storage)
      return hasData ? '数据可用，但未能保存缓存' : '本机数据读取失败';
    if (phase == DataPhase.failed) return '同步未完成';
    if (isBusy) return hasData ? '显示上次数据，正在更新' : '正在加载';
    return switch (source) {
      DataSource.demo => '正在浏览演示数据',
      DataSource.local => '本地数据',
      DataSource.cache => '上次同步的数据',
      DataSource.live => '已同步',
      DataSource.none => '尚未同步',
    };
  }

  String get description {
    final prefix = source == DataSource.cache ? '已保留上次数据，最新变更尚未确认。' : '';
    final detail = switch (problem) {
      DataProblem.loginRequired => '请完成学校认证后重新同步。',
      DataProblem.network => '无法连接校园服务，请检查网络或 WebVPN 后重试。',
      DataProblem.timeout => '校园服务响应超时，请稍后重试。',
      DataProblem.format => '学校返回的数据格式无法识别，请稍后重试或反馈。',
      DataProblem.unavailable => '服务暂不可用，请重试；这不代表没有记录。',
      DataProblem.partial => '当前列表可能不完整，请同步后核对。',
      DataProblem.storage =>
        hasData ? '本次数据已显示，下次离线可能无法恢复。' : '请检查本机存储后重试，原有数据不会被自动覆盖。',
      null => switch (source) {
        DataSource.demo => '示例不代表你的真实校园记录。',
        DataSource.local => '仅保存在当前设备，不会自动同步学校变更。',
        DataSource.cache => '重要安排请以学校最新信息为准。',
        _ => isBusy ? '请稍候。' : '',
      },
    };
    return '$prefix$detail';
  }
}

class CampusDataException implements Exception {
  const CampusDataException(this.problem);
  final DataProblem problem;
  @override
  String toString() => 'CampusDataException(${problem.name})';
}

DataProblem dataProblem(Object error) {
  if (error is CampusDataException) return error.problem;
  if (error is TimeoutException) return DataProblem.timeout;
  if (error is FormatException) return DataProblem.format;
  if (error is DioException) {
    if (error.response?.statusCode == 401) return DataProblem.loginRequired;
    if ({
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    }.contains(error.type))
      return DataProblem.timeout;
    if (error.type == DioExceptionType.connectionError)
      return DataProblem.network;
  }
  return DataProblem.unavailable;
}
