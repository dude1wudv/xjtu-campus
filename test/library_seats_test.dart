import 'package:flutter_test/flutter_test.dart';
import 'package:xjtu_campus/features/library_seats/data/library_seat_areas.dart';
import 'package:xjtu_campus/features/library_seats/domain/library_seat.dart';
import 'package:xjtu_campus/features/library_seats/data/live_library_seats_repository.dart';

class _CountingRepo extends LiveLibrarySeatsRepository {
  _CountingRepo() : super(api: null);

  int reserves = 0;

  @override
  Future<BookSeatResult> reserve({
    required String seatId,
    required String areaCode,
  }) async {
    reserves += 1;
    return BookSeatResult(
      success: false,
      message: 'fail',
      seatId: seatId,
      attempts: reserves,
    );
  }

  @override
  Future<LibrarySeatsSnapshot> listSeats(String areaCode) async {
    return LibrarySeatsSnapshot(
      areaCode: areaCode,
      seats: const [
        LibrarySeat(
          id: 'Y002',
          areaCode: 'west3B',
          occupancy: SeatOccupancy.occupied,
        ),
        LibrarySeat(
          id: 'Y003',
          areaCode: 'west3B',
          occupancy: SeatOccupancy.free,
        ),
      ],
      live: true,
      reachable: true,
    );
  }
}

void main() {
  test('guessAreaForSeat matches Toolbox heuristics', () {
    expect(LibrarySeatAreas.guessAreaForSeat('Y002'), 'west3B');
    expect(LibrarySeatAreas.guessAreaForSeat('X115'), 'east3A');
    expect(LibrarySeatAreas.guessAreaForSeat('Q015'), 'north4southwest');
    expect(LibrarySeatAreas.guessAreaForSeat('T001'), 'north4southeast');
  });

  test('LibrarySeatScheduleConfig roundtrip', () {
    final cfg = LibrarySeatScheduleConfig(
      preferredSeatId: 'Y002',
      preferredAreaCode: 'west3B',
      startAt: DateTime.utc(2026, 9, 16, 8, 0),
      fallbackAreaCodes: const ['west3B', 'east3A'],
      maxAttempts: 5,
      delayMs: 1200,
    );
    final restored = LibrarySeatScheduleConfig.fromJson(cfg.toJson());
    expect(restored.preferredSeatId, 'Y002');
    expect(restored.maxAttempts, 5);
    expect(restored.fallbackAreaCodes, ['west3B', 'east3A']);
  });

  test('reserveWithFallback stops at maxAttempts (no infinite loop)', () async {
    final repo = _CountingRepo();
    final result = await repo.reserveWithFallback(
      preferredSeatId: 'Y002',
      preferredAreaCode: 'west3B',
      fallbackAreaCodes: const ['west3B'],
      maxAttempts: 2,
      delayMs: 1000,
    );
    expect(result.success, isFalse);
    expect(result.attempts, lessThanOrEqualTo(3));
    expect(repo.reserves, lessThanOrEqualTo(3));
  });
}
