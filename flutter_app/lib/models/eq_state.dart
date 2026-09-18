import 'package:flutter/foundation.dart';
import '../src/rust/api/simple.dart';

enum EqFilterType {
  peaking,
  lowShelf,
  highShelf,
}

enum YAxisScaleMode {
  crinStandard, // 30 dB to 85 dB SPL (55 dB range, 60 dB reference) - Crinacle / Squiglink Standard
  crin50Db,     // 35 dB to 85 dB SPL (50 dB range, 60 dB reference) - Crin's Graphs 101 Sweet Spot
  deltaGain,    // -15 dB to +15 dB Gain (30 dB range, 0 dB reference) - Classic DAW Filter Mode
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
  List<Point> headphoneCurveL = [];
  List<Point> headphoneCurveR = [];
  List<Point> headphoneCurveMid = [];
  bool isDualChannel = false;
  bool matchChannels = false;
  double avgImbalanceDb = 0.0;
  double maxImbalanceDb = 0.0;
  double maxImbalanceFreq = 0.0;
  List<ActiveFilter> channelMatchFiltersL = [];
  List<ActiveFilter> channelMatchFiltersR = [];
  List<Point> matchedCurveL = [];
  List<Point> matchedCurveR = [];
  
  String? selectedOutputDevice;
  HeadphoneModel? activeHeadphone;
  bool normalizeToTarget = false;
  YAxisScaleMode scaleMode = YAxisScaleMode.crinStandard;
  
  double tilt = 0.0;
  double bass = 0.0;
  double treble = 0.0;
  double earGain = 0.0;
  String? currentTargetName;
  List<Point> baseTargetCurve = [];

  double preampGain = 0.0;
  bool isComputingAutoeq = false;
  bool isAutoEqActive = false;
  bool isBypassActive = false;
  String crossfeedMode = 'Off';
  CrossfeedConfig? crossfeedConfig;

  double get autoGainOffsetDb {
    if (nodes.isEmpty) return preampGain;
    final avgGain = nodes.fold<double>(0.0, (sum, n) => sum + n.gain) / nodes.length;
    return -(avgGain + preampGain);
  }

  void toggleBypass() {
    isBypassActive = !isBypassActive;
    notifyListeners();
  }

  void setBypass(bool active) {
    if (isBypassActive != active) {
      isBypassActive = active;
      notifyListeners();
    }
  }

  void setCrossfeedMode(String mode) {
    crossfeedMode = mode;
    try {
      final queryMode = mode.toLowerCase() == 'subtle' ? 'default' : mode.toLowerCase();
      crossfeedConfig = getCrossfeedPresetByName(modeName: queryMode);
    } catch (_) {}
    notifyListeners();
  }

  void setScaleMode(YAxisScaleMode mode) {
    scaleMode = mode;
    notifyListeners();
  }

  void toggleNormalize() {
    normalizeToTarget = !normalizeToTarget;
    notifyListeners();
  }

  void toggleMatchChannels() {
    if (!isDualChannel || headphoneCurveL.isEmpty || headphoneCurveR.isEmpty) return;
    
    matchChannels = !matchChannels;
    if (matchChannels) {
      final res = matchRawChannels(
        rawL: headphoneCurveL,
        rawR: headphoneCurveR,
        maxBands: BigInt.from(6),
      );
      channelMatchFiltersL = res.leftFilters;
      channelMatchFiltersR = res.rightFilters;
      matchedCurveL = res.matchedL;
      matchedCurveR = res.matchedR;
    }
    notifyListeners();
  }

  void simulateDualChannel() {
    if (headphoneCurve.isEmpty && headphoneCurveMid.isEmpty) return;
    final base = headphoneCurve.isNotEmpty ? headphoneCurve : headphoneCurveMid;
    final res = simulateDualChannelImbalance(baseCurve: base, seed: 42);
    _applyDualResult(res);
  }

  void loadCustomCsv(String content, String name) {
    final res = parseCsvMeasurement(csvContent: content);
    activeHeadphone = HeadphoneModel(
      brand: 'Custom Import',
      model: name,
      formFactor: res.isDualChannel ? 'Dual-Channel Measurement' : 'Measurement',
    );
    _applyDualResult(res);
  }

  void _applyDualResult(DualMeasurementResult res) {
    headphoneCurveL = res.rawL;
    headphoneCurveR = res.rawR;
    headphoneCurveMid = res.rawMid;
    headphoneCurve = res.rawMid.isNotEmpty ? res.rawMid : res.rawL;
    isDualChannel = res.isDualChannel;
    avgImbalanceDb = res.avgImbalanceDb;
    maxImbalanceDb = res.maxImbalanceDb;
    maxImbalanceFreq = res.maxImbalanceFreq;
    matchChannels = false;
    channelMatchFiltersL = [];
    channelMatchFiltersR = [];
    matchedCurveL = [];
    matchedCurveR = [];
    notifyListeners();
  }

  void updateModifiers({double? newTilt, double? newBass, double? newTreble, double? newEarGain}) {
    if (newTilt != null) tilt = newTilt;
    if (newBass != null) bass = newBass;
    if (newTreble != null) treble = newTreble;
    if (newEarGain != null) earGain = newEarGain;
    _recalculateTarget();
  }

  void resetModifiers() {
    tilt = 0.0;
    bass = 0.0;
    treble = 0.0;
    earGain = 0.0;
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
      final dual = getDualHeadphoneCurve(filePath: model.filePath!);
      _applyDualResult(dual);
    } else {
      clearHeadphone();
    }
  }

  void clearHeadphone() {
    activeHeadphone = null;
    headphoneCurve = [];
    headphoneCurveL = [];
    headphoneCurveR = [];
    headphoneCurveMid = [];
    isDualChannel = false;
    matchChannels = false;
    avgImbalanceDb = 0.0;
    maxImbalanceDb = 0.0;
    maxImbalanceFreq = 0.0;
    channelMatchFiltersL = [];
    channelMatchFiltersR = [];
    matchedCurveL = [];
    matchedCurveR = [];
    notifyListeners();
  }

  void addNode(EqNode node) {
    nodes.add(node);
    selectedIndex = nodes.length - 1;
    notifyListeners();
  }

  void removeNode(int index) {
    if (index < 0 || index >= nodes.length) return;
    nodes.removeAt(index);
    if (selectedIndex == index) {
      selectedIndex = null;
    } else if (selectedIndex != null && selectedIndex! > index) {
      selectedIndex = selectedIndex! - 1;
    }
    notifyListeners();
  }

  void clearNodes() {
    nodes.clear();
    selectedIndex = null;
    preampGain = 0.0;
    notifyListeners();
  }

  void updateNode(int index, EqNode newNode) {
    if (index >= 0 && index < nodes.length) {
      nodes[index] = newNode;
      notifyListeners();
    }
  }

  void selectNode(int? index) {
    selectedIndex = index;
    notifyListeners();
  }

  void setComputingAutoeq(bool computing) {
    isComputingAutoeq = computing;
    notifyListeners();
  }

  void setPreampGain(double gain) {
    preampGain = gain;
    notifyListeners();
  }

  void loadUserPreset(UserPresetModel preset) {
    nodes.clear();
    for (final f in preset.filters) {
      EqFilterType t = EqFilterType.peaking;
      if (f.filterType == FilterType.lowShelf) t = EqFilterType.lowShelf;
      if (f.filterType == FilterType.highShelf) t = EqFilterType.highShelf;
      nodes.add(EqNode(freq: f.freq, gain: f.gain, q: f.q, type: t));
    }
    preampGain = preset.preamp;
    selectedIndex = nodes.isNotEmpty ? 0 : null;
    notifyListeners();
  }

  void triggerUpdate() {
    notifyListeners();
  }
}
