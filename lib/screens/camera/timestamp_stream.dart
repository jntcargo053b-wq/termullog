import 'dart:async';

// FIX: Singleton dengan StreamController.broadcast() yang TIDAK pernah di-close.
// Pola lama (close() di dispose()) mematikan controller secara permanen —
// setelah dipanggil, semua akses berikutnya throw "Cannot add event after closing".
// Solusi: pisahkan stop-timer (dispose) dari tutup-controller (tidak pernah dilakukan).
// Controller broadcast boleh idle tanpa subscriber tanpa membuang memori.

class TimestampStream {
  static final TimestampStream _instance = TimestampStream._internal();
  factory TimestampStream() => _instance;
  TimestampStream._internal();

  // Broadcast controller TIDAK pernah di-close selama lifecycle app.
  final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();

  Timer? _timer;
  int _listenerCount = 0;

  Stream<DateTime> get stream {
    _ensureRunning();
    return _controller.stream;
  }

  // Dipanggil oleh widget saat mulai listen — opsional tapi eksplisit.
  void acquire() {
    _listenerCount++;
    _ensureRunning();
  }

  // Dipanggil oleh widget saat dispose — berhenti jika tidak ada listener.
  void release() {
    if (_listenerCount > 0) _listenerCount--;
    if (_listenerCount == 0) _pauseTimer();
  }

  void _ensureRunning() {
    if (_timer != null) return;
    // Emit segera agar widget langsung mendapat nilai saat pertama subscribe.
    _controller.add(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_controller.isClosed) _controller.add(DateTime.now());
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // dispose() hanya menghentikan timer — controller TIDAK di-close.
  // Singleton dapat dipakai kembali setelah dispose() tanpa error.
  void dispose() {
    _pauseTimer();
    _listenerCount = 0;
  }
}
