import 'dart:async';

class TimestampStream {
  static final TimestampStream _instance = TimestampStream._internal();
  factory TimestampStream() => _instance;
  TimestampStream._internal();

  final StreamController<DateTime> _controller =
      StreamController<DateTime>.broadcast();
  Timer? _timer;

  Stream<DateTime> get stream {
    _start();
    return _controller.stream;
  }

  void _start() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _controller.add(DateTime.now());
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }
}
