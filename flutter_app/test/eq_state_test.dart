import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/eq_state.dart';
import 'package:flutter_app/src/rust/api/simple.dart';

void main() {
  group('EqState Frontend Logic Tests', () {
    test('Bypass state toggling and level matching calculation', () {
      final state = EqState();
      expect(state.isBypassActive, isFalse);

      state.toggleBypass();
      expect(state.isBypassActive, isTrue);

      state.toggleBypass();
      expect(state.isBypassActive, isFalse);

      state.setBypass(true);
      expect(state.isBypassActive, isTrue);

      // Verify level matching auto-gain offset calculation
      state.nodes = [
        EqNode(freq: 100.0, gain: 4.0, q: 1.0),
        EqNode(freq: 1000.0, gain: 2.0, q: 1.0),
      ];
      state.preampGain = -1.0;
      // Average gain is (4.0 + 2.0)/2 = 3.0. With preamp -1.0, net is 2.0 dB.
      // autoGainOffsetDb = -(3.0 + (-1.0)) = -2.0 dB.
      expect(state.autoGainOffsetDb, closeTo(-2.0, 0.001));
    });

    test('Crossfeed mode switching', () {
      final state = EqState();
      expect(state.crossfeedMode, 'Off');

      state.setCrossfeedMode('Subtle');
      expect(state.crossfeedMode, 'Subtle');

      state.setCrossfeedMode('Studio');
      expect(state.crossfeedMode, 'Studio');

      state.setCrossfeedMode('Off');
      expect(state.crossfeedMode, 'Off');
    });

    test('loadUserPreset applies filters and preamp to nodes', () {
      final state = EqState();
      final preset = UserPresetModel(
        id: 1,
        name: 'Test Audiophile Preset',
        createdAt: '2026-09-16 10:00:00',
        filters: const [
          ActiveFilter(filterType: FilterType.lowShelf, freq: 105.0, gain: 5.5, q: 0.71),
          ActiveFilter(filterType: FilterType.peaking, freq: 2400.0, gain: -3.0, q: 2.0),
          ActiveFilter(filterType: FilterType.highShelf, freq: 10000.0, gain: 1.5, q: 0.71),
        ],
        preamp: -4.5,
        headphoneName: 'Sennheiser HD600',
      );

      state.loadUserPreset(preset);

      expect(state.nodes.length, 3);
      expect(state.nodes[0].type, EqFilterType.lowShelf);
      expect(state.nodes[0].freq, 105.0);
      expect(state.nodes[0].gain, 5.5);
      expect(state.nodes[1].type, EqFilterType.peaking);
      expect(state.nodes[1].freq, 2400.0);
      expect(state.nodes[1].gain, -3.0);
      expect(state.nodes[2].type, EqFilterType.highShelf);
      expect(state.nodes[2].freq, 10000.0);
      expect(state.nodes[2].gain, 1.5);
      expect(state.preampGain, -4.5);
      expect(state.selectedIndex, 0);
    });
  });
}
