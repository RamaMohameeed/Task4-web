import 'package:flutter/material.dart';

class MetricsProvider with ChangeNotifier {
  final List<int> _durations = [];

  void addDuration(int ms) {
    _durations.add(ms);
    notifyListeners();
  }

  List<int> get durations => List.unmodifiable(_durations);

  double get averageMs {
    if (_durations.isEmpty) return 0;
    final sum = _durations.fold<int>(0, (a, b) => a + b);
    return sum / _durations.length;
  }

  void clear() {
    _durations.clear();
    notifyListeners();
  }
}
