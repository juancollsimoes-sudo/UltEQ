import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/eq_state.dart';

void main() {
  test('EqState initializes with standard default values', () {
    final state = EqState();
    expect(state.nodes.isNotEmpty, isTrue);
    expect(state.preampGain, 0.0);
    expect(state.isBypassActive, isFalse);
    expect(state.crossfeedMode, 'Off');
  });
}
