import 'package:flutter/foundation.dart';
import '../src/rust/api/simple.dart';

enum EqFilterType {
  peaking,
  lowShelf,
  highShelf,
}

class EqNode {
  double freq;
  double gain;
  double q;
  EqFilterType type;

  EqNode({
    required this.freq,
    required this.gain,
    required this.q,
    this.type = EqFilterType.peaking,
  });
}

class EqState extends ChangeNotifier {
  List<EqNode> nodes = [EqNode(freq: 1000.0, gain: 0.0, q: 0.707)];
  int? selectedIndex;
  List<Point> targetCurve = [];
  List<Point> headphoneCurve = [];

  void loadTarget(String targetName) {
    targetCurve = getTargetCurve(dbPath: 'ulteq.db', targetName: targetName);
    notifyListeners();
  }

  Future<void> loadHeadphone(String filePath) async {
    // getHeadphoneCurve from FFI is synchronous in this bridge
    headphoneCurve = getHeadphoneCurve(filePath: filePath);
    notifyListeners();
  }

  void addNode(EqNode node) {
    nodes.add(node);
    selectedIndex = nodes.length - 1;
    notifyListeners();
  }

  void removeNode(int index) {
    nodes.removeAt(index);
    if (selectedIndex == index) {
      selectedIndex = null;
    } else if (selectedIndex != null && selectedIndex! > index) {
      selectedIndex = selectedIndex! - 1;
    }
    notifyListeners();
  }

  void updateNode(int index, EqNode newNode) {
    nodes[index] = newNode;
    notifyListeners();
  }

  void selectNode(int? index) {
    selectedIndex = index;
    notifyListeners();
  }

  void triggerUpdate() {
    notifyListeners();
  }
}
