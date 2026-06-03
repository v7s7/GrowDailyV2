import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  void track(String event, {Map<String, Object?> props = const {}}) {
    debugPrint('[Analytics] $event ${props.isEmpty ? '' : props}');
  }
}
