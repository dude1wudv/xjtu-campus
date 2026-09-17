import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/network/campus_session.dart';
import '../domain/library_seat.dart';

/// HTTP client for `http://rg.lib.xjtu.edu.cn:8086` (campus-net).
///
/// No credentials are logged. Session cookies come from Dio's CookieJar if set
/// by the caller; this client itself never stores passwords.
class LibrarySeatApi {
  LibrarySeatApi({
    this.session,
    Dio? dio,
    CookieJar? cookieJar,
    String baseUrl = defaultBaseUrl,
    Duration? connectTimeout,
  })  : baseUrl = baseUrl,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: connectTimeout ?? const Duration(seconds: 6),
                receiveTimeout: const Duration(seconds: 12),
                followRedirects: true,
                validateStatus: (code) => code != null && code < 500,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
                },
              ),
            ) {
    if (dio == null && (cookieJar != null || session != null)) {
      _dio.interceptors.add(CookieManager(cookieJar ?? session!.jar));
    }
  }

  static const defaultBaseUrl = 'http://rg.lib.xjtu.edu.cn:8086';

  final CampusSession? session;
  final Dio _dio;

  String _url(String path) {
    final absolute = Uri.parse(baseUrl).resolve(path).toString();
    return session?.resolveUrl(absolute) ?? absolute;
  }
  final String baseUrl;

  /// Probe reachability (campus-net).
  Future<bool> isReachable() async {
    try {
      final res = await _dio.get<dynamic>(
        _url('/'),
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
          followRedirects: true,
        ),
      );
      return res.statusCode != null && res.statusCode! < 500;
    } on DioException {
      return false;
    } on Object {
      return false;
    }
  }

  Future<LibrarySeatsSnapshot> listSeats(String areaCode) async {
    try {
      final res = await _dio.get<dynamic>(
        _url('/qseat'),
        queryParameters: {'sp': areaCode},
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'application/json,text/plain,*/*'},
        ),
      );
      final status = res.statusCode ?? 0;
      if (status == 401 || status == 403) {
        return LibrarySeatsSnapshot(
          areaCode: areaCode,
          seats: const [],
          live: false,
          reachable: true,
          needsAuth: true,
          banner: AppStrings.librarySeatsAuthHint,
          fetchedAt: DateTime.now(),
        );
      }
      final body = res.data?.toString() ?? '';
      if (body.trim().isEmpty) {
        throw StateError('empty qseat body');
      }
      if (body.contains('login') &&
          body.contains('password') &&
          !body.trimLeft().startsWith('{')) {
        return LibrarySeatsSnapshot(
          areaCode: areaCode,
          seats: const [],
          live: false,
          reachable: true,
          needsAuth: true,
          banner: AppStrings.librarySeatsAuthHint,
          fetchedAt: DateTime.now(),
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw StateError('qseat not a map');
      }
      final seatMap = decoded['seat'];
      final seats = <LibrarySeat>[];
      if (seatMap is Map) {
        seatMap.forEach((k, v) {
          final SeatOccupancy occ;
          if (v == 0 || v == '0') {
            occ = SeatOccupancy.free;
          } else if (v == 1 || v == '1') {
            occ = SeatOccupancy.occupied;
          } else {
            occ = SeatOccupancy.unknown;
          }
          seats.add(
            LibrarySeat(
              id: k.toString(),
              areaCode: areaCode,
              occupancy: occ,
            ),
          );
        });
      }
      seats.sort((a, b) => a.id.compareTo(b.id));
      final free = seats.where((s) => s.isFree).length;
      return LibrarySeatsSnapshot(
        areaCode: areaCode,
        seats: seats,
        live: true,
        reachable: true,
        fetchedAt: DateTime.now(),
        banner: '实时空座 · $free/${seats.length}',
      );
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        return LibrarySeatsSnapshot(
          areaCode: areaCode,
          seats: const [],
          live: false,
          reachable: false,
          banner: AppStrings.librarySeatsCampusNetHint,
          fetchedAt: DateTime.now(),
        );
      }
      rethrow;
    }
  }

  /// Reserve a seat. Success if final URL contains `/seat/my/`.
  Future<BookSeatResult> reserve({
    required String seatId,
    required String areaCode,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        _url('/seat/'),
        queryParameters: {'kid': seatId, 'sp': areaCode},
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: {'Referer': _url('/seat/')},
        ),
      );
      final finalUrl = res.realUri.toString();
      final status = res.statusCode ?? 0;
      if (status == 401 || status == 403) {
        return const BookSeatResult(
          success: false,
          message: AppStrings.librarySeatsAuthHint,
        );
      }
      if (finalUrl.contains('/seat/my/') || finalUrl.contains('/my/')) {
        return BookSeatResult(
          success: true,
          message: '预约成功：$seatId',
          seatId: seatId,
        );
      }
      final body = res.data?.toString() ?? '';
      if (body.contains('已预约') || body.contains('预约成功')) {
        return BookSeatResult(
          success: true,
          message: '预约成功：$seatId',
          seatId: seatId,
        );
      }
      return BookSeatResult(
        success: false,
        message: '预约未成功（座位可能已被占）',
        seatId: seatId,
      );
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        return const BookSeatResult(
          success: false,
          message: AppStrings.librarySeatsCampusNetHint,
        );
      }
      return BookSeatResult(
        success: false,
        message: '预约请求失败：${e.message ?? e.type.name}',
        seatId: seatId,
      );
    }
  }

  Future<List<LibraryBooking>> myBookings() async {
    try {
      final res = await _dio.get<String>(
        _url('/seat/my/'),
        options: Options(responseType: ResponseType.plain),
      );
      if ((res.statusCode ?? 0) == 401 || (res.statusCode ?? 0) == 403) {
        throw StateError('auth');
      }
      final body = res.data ?? '';
      if ((body.toLowerCase().contains('login') && body.toLowerCase().contains('password')) ||
          body.contains('统一身份认证')) throw StateError('auth');
      return _parseMyBookings(body);
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        throw StateError('unreachable');
      }
      final res = await _dio.get<String>(
        _url('/my/'),
        options: Options(responseType: ResponseType.plain),
      );
      final body = res.data ?? '';
      if ((body.toLowerCase().contains('login') && body.toLowerCase().contains('password')) ||
          body.contains('统一身份认证')) throw StateError('auth');
      return _parseMyBookings(body);
    }
  }

  /// Best-effort cancel via discovered path or common patterns.
  Future<BookSeatResult> cancel(LibraryBooking booking) async {
    try {
      final path = booking.cancelPath;
      if (path != null && path.isNotEmpty) {
        final res = await _dio.get<dynamic>(
          _url(path),
          options: Options(responseType: ResponseType.plain),
        );
        if ((res.statusCode ?? 500) < 400) {
          return const BookSeatResult(success: true, message: '已提交取消');
        }
      }
      for (final probe in [
        '/seat/cancel/?kid=${booking.seatId}&sp=${booking.areaCode}',
        '/cancel/?kid=${booking.seatId}',
      ]) {
        try {
          final res = await _dio.get<dynamic>(
            _url(probe),
            options: Options(
              responseType: ResponseType.plain,
              validateStatus: (_) => true,
            ),
          );
          final text = res.data?.toString() ?? '';
          if ((res.statusCode ?? 500) < 400 && !text.contains('404')) {
            return const BookSeatResult(success: true, message: '已提交取消');
          }
        } on Object {
          continue;
        }
      }
      return const BookSeatResult(
        success: false,
        message: '未能自动取消，请在「我的预约」网页操作',
      );
    } on DioException catch (e) {
      if (_isNetworkFailure(e)) {
        return const BookSeatResult(
          success: false,
          message: AppStrings.librarySeatsCampusNetHint,
        );
      }
      return BookSeatResult(
        success: false,
        message: '取消失败：${e.message ?? e.type.name}',
      );
    }
  }

  List<LibraryBooking> _parseMyBookings(String html) {
    final bookings = <LibraryBooking>[];
    final seatRe = RegExp(r'\b([A-Z]?\d{2,4})\b');
    final cancelRe = RegExp(
      r'''href=["']([^"']*cancel[^"']*)["']''',
      caseSensitive: false,
    );
    final cancelPath = cancelRe.firstMatch(html)?.group(1);
    final statusRe = RegExp(r'(已预约|已取消|已离馆|超时未入馆|预约成功)[^<]{0,80}');
    final status = statusRe.firstMatch(html)?.group(0);

    final candidates = seatRe
        .allMatches(html)
        .map((m) => m.group(1)!)
        .where((id) => id.length >= 2)
        .toSet()
        .take(5);
    for (final id in candidates) {
      bookings.add(
        LibraryBooking(
          seatId: id,
          areaCode: '',
          statusLabel: status,
          cancelPath: cancelPath,
        ),
      );
    }
    return bookings;
  }

  bool _isNetworkFailure(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError;
  }
}
