import 'library_seat.dart';

abstract class LibrarySeatsRepository {
  Future<bool> isReachable();

  Future<LibrarySeatsSnapshot> listSeats(String areaCode);

  Future<BookSeatResult> reserve({
    required String seatId,
    required String areaCode,
  });

  Future<List<LibraryBooking>> myBookings();

  Future<BookSeatResult> cancel(LibraryBooking booking);

  /// Preferred seat first; then free seats in [fallbackAreaCodes].
  /// Stops on success or after [maxAttempts]. Delay ≥ [delayMs] between tries.
  Future<BookSeatResult> reserveWithFallback({
    required String preferredSeatId,
    required String preferredAreaCode,
    required List<String> fallbackAreaCodes,
    int maxAttempts = 8,
    int delayMs = 1500,
  });
}
