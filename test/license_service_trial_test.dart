import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/services/license_service.dart';

void main() {
  test('30 günlük deneme ilk anda 30 gün gösterir', () {
    final startedAt = DateTime.utc(2026, 8, 12, 10);
    expect(
      LicenseService.calculateTrialDaysRemaining(startedAt, now: startedAt),
      30,
    );
  });

  test('kısmi son gün bir gün olarak gösterilir ve bitince sıfırlanır', () {
    final startedAt = DateTime.utc(2026, 1, 1);
    expect(
      LicenseService.calculateTrialDaysRemaining(
        startedAt,
        now: startedAt.add(const Duration(days: 29, hours: 23)),
      ),
      1,
    );
    expect(
      LicenseService.calculateTrialDaysRemaining(
        startedAt,
        now: startedAt.add(const Duration(days: 30)),
      ),
      0,
    );
  });
}
