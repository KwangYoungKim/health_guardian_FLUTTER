import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:health_guardian_flutter/screens/meet_screen.dart';

void main() {
  group('filterGlitchLatLngPoints Tests', () {
    test('Empty and single item lists return as is', () {
      expect(filterGlitchLatLngPoints([]), isEmpty);
      final single = [const LatLng(37.5665, 126.9780)];
      expect(filterGlitchLatLngPoints(single).length, equals(1));
    });

    test('Filters out single extreme spike between normal points', () {
      final raw = [
        const LatLng(37.5665, 126.9780),
        const LatLng(37.5666, 126.9781), // normal ~15m
        const LatLng(38.5665, 127.9780), // extreme spike (~100km away)
        const LatLng(37.5667, 126.9782), // normal ~15m
      ];

      final filtered = filterGlitchLatLngPoints(raw);
      expect(filtered.length, equals(3));
      expect(filtered.any((p) => p.latitude == 38.5665), isFalse);
    });

    test('Preserves valid path when user moves to a new location cluster', () {
      final raw = [
        const LatLng(37.5665, 126.9780), // Start point A
        const LatLng(37.5800, 126.9900), // Moved to B (~1.8km away)
        const LatLng(37.5801, 126.9901), // Continued at B
      ];

      final filtered = filterGlitchLatLngPoints(raw);
      expect(filtered.length, equals(3));
    });

    test('Preserves continuous fast driving (car/vehicle travel)', () {
      // 80 km/h driving sample points (moving ~200m every 10 seconds)
      final drivingPoints = [
        const LatLng(37.5665, 126.9780),
        const LatLng(37.5680, 126.9800), // ~200m
        const LatLng(37.5695, 126.9820), // ~200m
        const LatLng(37.5710, 126.9840), // ~200m
        const LatLng(37.5725, 126.9860), // ~200m
      ];

      final filtered = filterGlitchLatLngPoints(drivingPoints);
      expect(filtered.length, equals(5));
    });
  });
}
