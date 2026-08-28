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
  
  String? selectedOutputDevice;
  HeadphoneModel? activeHeadphone;
  bool normalizeToTarget = false;
  
  double tilt = 0.0;
  double bass = 0.0;
  double treble = 0.0;
  double earGain = 0.0;
  String? currentTargetName;
  List<Point> baseTargetCurve = [];

  void toggleNormalize() {
    normalizeToTarget = !normalizeToTarget;
    notifyListeners();
  }

  void updateModifiers({double? newTilt, double? newBass, double? newTreble, double? newEarGain}) {
    if (newTilt != null) tilt = newTilt;
    if (newBass != null) bass = newBass;
    if (newTreble != null) treble = newTreble;
    if (newEarGain != null) earGain = newEarGain;
    _recalculateTarget();
  }

  void loadTarget(String targetName) {
    currentTargetName = targetName;
    baseTargetCurve = getTargetCurve(dbPath: 'ulteq.db', targetName: targetName);
    _recalculateTarget();
  }
  
  void _recalculateTarget() {
    if (baseTargetCurve.isEmpty) {
      targetCurve = [];
    } else {
      targetCurve = modifyTarget(baseTarget: baseTargetCurve, tilt: tilt, bass: bass, treble: treble, earGain: earGain);
    }
    notifyListeners();
  }

  Future<void> loadHeadphone(HeadphoneModel model) async {
    activeHeadphone = model;
    if (model.filePath != null) {
      headphoneCurve = getHeadphoneCurve(filePath: model.filePath!);
    } else {
      headphoneCurve = [];
    }
    notifyListeners();
  }

  void clearHeadphone() {
    activeHeadphone = null;
    headphoneCurve = [];
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
