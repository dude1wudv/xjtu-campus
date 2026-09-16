import '../domain/library_seat.dart';
import '../domain/library_seats_repository.dart';
import 'library_seat_api.dart';

class LiveLibrarySeatsRepository implements LibrarySeatsRepository {
  LiveLibrarySeatsRepository({LibrarySeatApi? api})
      : _api = api ?? LibrarySeatApi();

  final LibrarySeatApi _api;

  @override
  Future<bool> isReachable() => _api.isReachable();

  @override
  Future<LibrarySeatsSnapshot> listSeats(String areaCode) =>
      _api.listSeats(areaCode);

  @override
  Future<BookSeatResult> reserve({
    required String seatId,
    required String areaCode,
  }) =>
      _api.reserve(seatId: seatId, areaCode: areaCode);

  @override
  Future<List<LibraryBooking>> myBookings() => _api.myBookings();

  @override
  Future<BookSeatResult> cancel(LibraryBooking booking) => _api.cancel(booking);

  @override
  Future<BookSeatResult> reserveWithFallback({
    required String preferredSeatId,
    required String preferredAreaCode,
    required List<String> fallbackAreaCodes,
    int maxAttempts = 8,
    int delayMs = 1500,
  }) async {
    final n = maxAttempts.clamp(1, 30);
    final waitMs = delayMs < 1000 ? 1000 : delayMs;
    var attempts = 0;
    BookSeatResult? last;

    Future<BookSeatResult> attempt(String seatId, String area) async {
      if (attempts > 0) {
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
      attempts += 1;
      final r = await reserve(seatId: seatId, areaCode: area);
      return BookSeatResult(
        success: r.success,
        message: r.message,
        seatId: r.seatId ?? seatId,
        attempts: attempts,
      );
    }

    last = await attempt(preferredSeatId, preferredAreaCode);
    if (last.success) return last;

    final areas = <String>{
      preferredAreaCode,
      ...fallbackAreaCodes,
    }.where((e) => e.isNotEmpty).toList();

    while (attempts < n) {
      var madeProgress = false;
      for (final area in areas) {
        if (attempts >= n) break;
        final snap = await listSeats(area);
        if (!snap.reachable) {
          return BookSeatResult(
            success: false,
            message: snap.banner ?? '校园网不可达',
            attempts: attempts,
          );
        }
        if (snap.needsAuth) {
          return BookSeatResult(
            success: false,
            message: snap.banner ?? '需要登录',
            attempts: attempts,
          );
        }
        final free = snap.freeSeats;
        if (free.isEmpty) continue;
        final preferred =
            free.where((s) => s.id == preferredSeatId).toList(growable: false);
        final ordered = preferred.isNotEmpty ? preferred : free;
        for (final seat in ordered) {
          if (attempts >= n) break;
          madeProgress = true;
          last = await attempt(seat.id, area);
          if (last.success) return last;
        }
      }
      if (!madeProgress) {
        // No free seats this sweep — still count a paced wait before next sweep.
        if (attempts >= n) break;
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        attempts += 1; // count empty sweep toward N so we cannot loop forever
        last = BookSeatResult(
          success: false,
          message: '暂无空座，继续等待…（$attempts/$n）',
          attempts: attempts,
        );
      }
    }

    return last ??
        BookSeatResult(
          success: false,
          message: '已尝试 $attempts 次，未约到座位（已停止）',
          attempts: attempts,
        );
  }
}
