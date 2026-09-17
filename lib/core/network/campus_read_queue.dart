import 'dart:async';
import 'dart:collection';

/// Bound expensive service syncs (each may create a WebView). This queue is
/// session-scoped; cached UI emission does not release the network slot early.
class CampusReadQueue {
  final Queue<Completer<void>> _waiting = Queue();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active >= 2) {
      final gate = Completer<void>();
      _waiting.add(gate);
      await gate.future;
    } else {
      _active++;
    }
    try {
      return await action();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
