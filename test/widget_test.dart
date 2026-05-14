import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_invaders_dashboard/models/telemetry_model.dart';

void main() {
  test('TelemetryData.fromJson parses correctly', () {
    final json = {
      'level': 10,
      'score': 124000,
      'bossHP': 23,
      'maxBossHP': 45,
      'enemies': 7,
      'state': 'BOSS',
      'projectiles': 4,
      'accuracy': 89,
      'comboColor': 6,
      'mode': 'FINAL_BOSS',
      'simonStage': 0,
      'beatSaber': false,
      'leds': [0, 0, 1, 1, 2, 3, 4, 5, 6, 7],
    };

    final t = TelemetryData.fromJson(json);

    expect(t.level, 10);
    expect(t.score, 124000);
    expect(t.bossHP, 23);
    expect(t.maxBossHP, 45);
    expect(t.enemies, 7);
    expect(t.state, 'BOSS');
    expect(t.projectiles, 4);
    expect(t.accuracy, 89);
    expect(t.comboColor, 6);
    expect(t.mode, 'FINAL_BOSS');
    expect(t.simonStage, 0);
    expect(t.beatSaber, false);
    expect(t.leds.length, 10);
    expect(t.bossHPRatio, closeTo(0.511, 0.01));
    expect(t.isBossFight, true);
  });

  test('TelemetryData.empty has sane defaults', () {
    final t = TelemetryData.empty;
    expect(t.level, 0);
    expect(t.score, 0);
    expect(t.leds.isEmpty, true);
    expect(t.state, 'IDLE');
  });
}
