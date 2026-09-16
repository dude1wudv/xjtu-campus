import 'package:equatable/equatable.dart';

enum SeatOccupancy { free, occupied, unknown }

class LibraryArea extends Equatable {
  const LibraryArea({required this.code, required this.label});

  final String code;
  final String label;

  @override
  List<Object?> get props => [code, label];
}

class LibrarySeat extends Equatable {
  const LibrarySeat({
    required this.id,
    required this.areaCode,
    required this.occupancy,
  });

  final String id;
  final String areaCode;
  final SeatOccupancy occupancy;

  bool get isFree => occupancy == SeatOccupancy.free;

  @override
  List<Object?> get props => [id, areaCode, occupancy];
}

class LibraryBooking extends Equatable {
  const LibraryBooking({
    required this.seatId,
    required this.areaCode,
    this.statusLabel,
    this.cancelPath,
    this.rawSnippet,
  });

  final String seatId;
  final String areaCode;
  final String? statusLabel;
  final String? cancelPath;
  final String? rawSnippet;

  @override
  List<Object?> get props => [seatId, areaCode, statusLabel, cancelPath];
}

class LibrarySeatsSnapshot extends Equatable {
  const LibrarySeatsSnapshot({
    required this.areaCode,
    required this.seats,
    required this.live,
    this.banner,
    this.fetchedAt,
    this.reachable = true,
    this.needsAuth = false,
  });

  final String areaCode;
  final List<LibrarySeat> seats;
  final bool live;
  final String? banner;
  final DateTime? fetchedAt;
  final bool reachable;
  final bool needsAuth;

  List<LibrarySeat> get freeSeats =>
      seats.where((s) => s.isFree).toList(growable: false);

  @override
  List<Object?> get props =>
      [areaCode, seats, live, banner, fetchedAt, reachable, needsAuth];
}

class BookSeatResult extends Equatable {
  const BookSeatResult({
    required this.success,
    required this.message,
    this.seatId,
    this.attempts = 1,
  });

  final bool success;
  final String message;
  final String? seatId;
  final int attempts;

  @override
  List<Object?> get props => [success, message, seatId, attempts];
}

/// User-configured scheduled reservation + fallback.
class LibrarySeatScheduleConfig extends Equatable {
  const LibrarySeatScheduleConfig({
    required this.preferredSeatId,
    required this.preferredAreaCode,
    required this.startAt,
    required this.fallbackAreaCodes,
    this.maxAttempts = 8,
    this.delayMs = 1500,
    this.enabled = true,
  });

  final String preferredSeatId;
  final String preferredAreaCode;
  final DateTime startAt;
  final List<String> fallbackAreaCodes;
  final int maxAttempts;
  final int delayMs;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'preferredSeatId': preferredSeatId,
        'preferredAreaCode': preferredAreaCode,
        'startAt': startAt.toIso8601String(),
        'fallbackAreaCodes': fallbackAreaCodes,
        'maxAttempts': maxAttempts,
        'delayMs': delayMs,
        'enabled': enabled,
      };

  factory LibrarySeatScheduleConfig.fromJson(Map<String, dynamic> json) {
    final areas = json['fallbackAreaCodes'];
    return LibrarySeatScheduleConfig(
      preferredSeatId: json['preferredSeatId']?.toString() ?? '',
      preferredAreaCode: json['preferredAreaCode']?.toString() ?? '',
      startAt: DateTime.tryParse(json['startAt']?.toString() ?? '') ??
          DateTime.now(),
      fallbackAreaCodes: areas is List
          ? areas.map((e) => e.toString()).toList()
          : const <String>[],
      maxAttempts: (json['maxAttempts'] as num?)?.toInt() ?? 8,
      delayMs: (json['delayMs'] as num?)?.toInt() ?? 1500,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
        preferredSeatId,
        preferredAreaCode,
        startAt,
        fallbackAreaCodes,
        maxAttempts,
        delayMs,
        enabled,
      ];
}
