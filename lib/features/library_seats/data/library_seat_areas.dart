import '../domain/library_seat.dart';

/// Area codes aligned with XJTU-Toolbox / historical campus notes.
abstract final class LibrarySeatAreas {
  static const List<LibraryArea> all = [
    LibraryArea(code: 'north2east', label: '北楼二层外文库（东）'),
    LibraryArea(code: 'north2west', label: '北楼二层外文库（西）'),
    LibraryArea(code: 'north2elian', label: '二层连廊及流通大厅'),
    LibraryArea(code: 'south2', label: '南楼二层大厅'),
    LibraryArea(code: 'east3A', label: '北楼三层 ILibrary-A（东）'),
    LibraryArea(code: 'west3B', label: '北楼三层 ILibrary-B（西）'),
    LibraryArea(code: 'eastnorthda', label: '大屏辅学空间'),
    LibraryArea(code: 'south3middle', label: '南楼三层中段'),
    LibraryArea(code: 'north4west', label: '北楼四层西侧'),
    LibraryArea(code: 'north4middle', label: '北楼四层中间'),
    LibraryArea(code: 'north4east', label: '北楼四层东侧'),
    LibraryArea(code: 'north4southwest', label: '北楼四层西南侧'),
    LibraryArea(code: 'north4southeast', label: '北楼四层东南侧'),
  ];

  static String? labelFor(String code) {
    for (final a in all) {
      if (a.code == code) return a.label;
    }
    return null;
  }

  /// Heuristic seat-id prefix → area (Toolbox-compatible).
  static String guessAreaForSeat(String seatId) {
    final id = seatId.trim().toUpperCase();
    if (id.isEmpty) return 'south3middle';
    final c = id[0];
    switch (c) {
      case 'A':
      case 'B':
        return 'north2elian';
      case 'D':
      case 'E':
        return 'north2east';
      case 'C':
        return 'south2';
      case 'N':
        return 'north2west';
      case 'Y':
        return 'west3B';
      case 'P':
        return 'eastnorthda';
      case 'X':
        return 'east3A';
      case 'K':
      case 'L':
      case 'M':
        return 'north4west';
      case 'J':
        return 'north4middle';
      case 'H':
      case 'F':
      case 'G':
        return 'north4east';
      case 'Q':
        return 'north4southwest';
      case 'T':
        return 'north4southeast';
      default:
        return 'south3middle';
    }
  }
}
