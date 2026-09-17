import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Invalidates service snapshots after changing transport or importing cookies.
class CampusConnectionRevision extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

final campusConnectionRevisionProvider =
    NotifierProvider<CampusConnectionRevision, int>(CampusConnectionRevision.new);

class CampusConnectionBusy extends Notifier<bool> {
  @override
  bool build() => false;

  void setBusy(bool value) { if (ref.mounted) state = value; }
}

final campusConnectionBusyProvider =
    NotifierProvider<CampusConnectionBusy, bool>(CampusConnectionBusy.new);
