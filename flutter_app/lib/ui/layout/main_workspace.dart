import 'package:flutter/material.dart';
import 'package:flutter_app/ui/canvas/logarithmic_canvas.dart';
import 'package:flutter_app/ui/controls/band_list_panel.dart';
import 'package:flutter_app/ui/controls/target_adjustments_panel.dart';
import 'package:flutter_app/ui/sidebar/sidebar.dart';
import 'package:flutter_app/models/eq_state.dart';
import 'package:flutter_app/src/rust/api/simple.dart';
import 'package:flutter_app/ui/theme/app_theme.dart';

class MainWorkspace extends StatefulWidget {
  const MainWorkspace({super.key});

  @override
  State<MainWorkspace> createState() => _MainWorkspaceState();
}

class _MainWorkspaceState extends State<MainWorkspace> with SingleTickerProviderStateMixin {
  late final EqState _eqState;
  bool _isSidebarOpen = true;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _eqState = EqState();
    _initDefaultDevice();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseOpacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _initDefaultDevice() {
    try {
      final devices = getAudioDevices();
      if (devices.isNotEmpty) {
        _eqState.selectedOutputDevice = devices.first;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _eqState.dispose();
    super.dispose();
  }

  Future<void> _showAudioConfigDialog() async {
    final devices = getAudioDevices();
    String? selected = _eqState.selectedOutputDevice ?? (devices.isNotEmpty ? devices.first : null);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: AppColors.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.borderSubtle),
              ),
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.volume_up, size: 18, color: AppColors.emeraldLight),
                        const SizedBox(width: 8),
                        const Text(
                          'Audio Output Stream',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select the destination audio sink for real-time DSP filter convolution:',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selected,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceRaised,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
                          items: devices.map((d) {
                            return DropdownMenuItem(
                              value: d,
                              child: Text(
                                d,
                                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => selected = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => Navigator.pop(context, selected),
                          child: const Text('Connect Output'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      _eqState.selectedOutputDevice = result;
      _eqState.triggerUpdate();
      _showModernToast('Connected to $result', icon: Icons.volume_up, color: AppColors.emerald);
    }
  }

  void _runAutoEq() {
    if (_eqState.headphoneCurve.isEmpty || _eqState.targetCurve.isEmpty) {
      _showModernToast('Please select a Headphone and Target Curve first', icon: Icons.warning_amber, color: AppColors.amber);
      return;
    }

    _eqState.setComputingAutoeq(true);
    try {
      final filters = generateAutoeq(
        headphone: _eqState.headphoneCurve,
        target: _eqState.targetCurve,
        bands: BigInt.from(10),
      );

      _eqState.nodes.clear();
      for (final f in filters) {
        EqFilterType nodeType = EqFilterType.peaking;
        if (f.filterType == FilterType.lowShelf) nodeType = EqFilterType.lowShelf;
        if (f.filterType == FilterType.highShelf) nodeType = EqFilterType.highShelf;
        _eqState.nodes.add(EqNode(freq: f.freq, gain: f.gain, q: f.q, type: nodeType));
      }
      _eqState.selectedIndex = _eqState.nodes.isNotEmpty ? 0 : null;
      _eqState.triggerUpdate();

      final shelfCount = filters.where((f) => f.filterType == FilterType.lowShelf).length;
      final peakCount = filters.where((f) => f.filterType == FilterType.peaking).length;

      _showModernToast(
        'AutoEq generated $shelfCount Low Shelf + $peakCount Peaking filters',
        icon: Icons.auto_awesome,
        color: AppColors.primaryLight,
      );
    } catch (e) {
      _showModernToast('AutoEq failed: $e', icon: Icons.error_outline, color: AppColors.rose);
    } finally {
      _eqState.setComputingAutoeq(false);
    }
  }

  void _applyEq() {
    if (_eqState.selectedOutputDevice == null) {
      _showAudioConfigDialog();
      return;
    }

    final globalFilters = _eqState.nodes.map((n) {
      FilterType t = FilterType.peaking;
      if (n.type == EqFilterType.lowShelf) t = FilterType.lowShelf;
      if (n.type == EqFilterType.highShelf) t = FilterType.highShelf;
      return ActiveFilter(filterType: t, freq: n.freq, gain: n.gain, q: n.q);
    }).toList();

    try {
      if (_eqState.matchChannels && _eqState.channelMatchFiltersL.isNotEmpty) {
        final leftFilters = [..._eqState.channelMatchFiltersL, ...globalFilters];
        final rightFilters = [..._eqState.channelMatchFiltersR, ...globalFilters];
        applyStereoEqToDevice(
          deviceName: _eqState.selectedOutputDevice!,
          leftFilters: leftFilters,
          rightFilters: rightFilters,
        );
        _showModernToast(
          'Stereo Channel-Matched EQ active on ${_eqState.selectedOutputDevice}',
          icon: Icons.check_circle_outline,
          color: AppColors.emerald,
        );
      } else {
        applyEqToDevice(deviceName: _eqState.selectedOutputDevice!, filters: globalFilters);
        _showModernToast(
          'Equalization active on ${_eqState.selectedOutputDevice}',
          icon: Icons.check_circle_outline,
          color: AppColors.emerald,
        );
      }
    } catch (e) {
      _showModernToast('Error applying EQ: $e', icon: Icons.error_outline, color: AppColors.rose);
    }
  }

  void _showModernToast(String message, {required IconData icon, required Color color}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.35)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Command Header Dock (Linear / Raycast Style)
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: ListenableBuilder(
            listenable: _eqState,
            builder: (context, _) {
              final activeHp = _eqState.activeHeadphone;
              final hpLabel = activeHp != null ? '${activeHp.brand} ${activeHp.model}' : 'No Headphone';
              final targetLabel = _eqState.currentTargetName ?? 'No Target';
              final deviceLabel = _eqState.selectedOutputDevice ?? 'Select Audio Output';
              final canAutoEq = _eqState.headphoneCurve.isNotEmpty && _eqState.targetCurve.isNotEmpty;

              return Row(
                children: [
                  // Brand Lockup
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(color: AppColors.primaryGlow, blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.tune, size: 14, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Text('UltEQ', style: AppTypography.brand),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primaryLight.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'STUDIO',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),
                  Container(width: 1, height: 20, color: AppColors.borderSubtle),
                  const SizedBox(width: 16),

                  // Middle Context Chips (Overflow-protected)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Headphone Chip
                          _buildContextChip(
                            icon: Icons.headphones,
                            label: hpLabel,
                            isActive: activeHp != null,
                            activeColor: AppColors.cyanLight,
                            onTap: () {
                              if (!_isSidebarOpen) {
                                setState(() => _isSidebarOpen = true);
                              }
                            },
                          ),
                          const SizedBox(width: 8),

                          // Target Chip
                          _buildContextChip(
                            icon: Icons.adjust,
                            label: targetLabel,
                            isActive: _eqState.currentTargetName != null,
                            activeColor: AppColors.primaryLight,
                          ),
                          const SizedBox(width: 8),

                          // Output Device Chip
                          _buildContextChip(
                            icon: Icons.volume_up,
                            label: deviceLabel,
                            isActive: _eqState.selectedOutputDevice != null,
                            activeColor: AppColors.emeraldLight,
                            showPulseDot: true,
                            onTap: _showAudioConfigDialog,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Action Buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // AutoEq Button (Gradient Indigo)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: canAutoEq && !_eqState.isComputingAutoeq ? _runAutoEq : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: canAutoEq
                                ? const LinearGradient(
                                    colors: [AppColors.primary, AppColors.primaryDark],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: canAutoEq ? null : AppColors.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: canAutoEq ? AppColors.primaryLight.withOpacity(0.5) : AppColors.borderSubtle,
                            ),
                            boxShadow: canAutoEq
                                ? const [BoxShadow(color: AppColors.primaryGlow, blurRadius: 10, offset: Offset(0, 2))]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_eqState.isComputingAutoeq)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                )
                              else
                                Icon(
                                  Icons.auto_awesome,
                                  size: 13,
                                  color: canAutoEq ? Colors.white : AppColors.textMuted,
                                ),
                              const SizedBox(width: 6),
                              Text(
                                'AutoEq',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: canAutoEq ? Colors.white : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Apply EQ Button (Emerald Active)
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _applyEq,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.emerald, Color(0xFF059669)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.emeraldLight.withOpacity(0.5)),
                            boxShadow: const [
                              BoxShadow(color: AppColors.emeraldGlow, blurRadius: 10, offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 13, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Apply EQ',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),
                      Container(width: 1, height: 18, color: AppColors.borderSubtle),
                      const SizedBox(width: 8),

                      // Toggle Sidebar Button
                      Tooltip(
                        message: _isSidebarOpen ? 'Hide Library' : 'Show Library',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isSidebarOpen ? AppColors.cardHover : AppColors.card,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Icon(
                              _isSidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                              size: 15,
                              color: _isSidebarOpen ? AppColors.primaryLight : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        // 2. Middle & Bottom Studio Workspace
        Expanded(
          child: Row(
            children: [
              // Left: Filter Bands Inspector
              Container(
                width: 270,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: AppColors.borderSubtle)),
                ),
                child: BandListPanel(eqState: _eqState),
              ),

              // Center: Canvas + Bottom Target Adjustments Dock
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: LogarithmicCanvas(eqState: _eqState),
                    ),
                    TargetAdjustmentsPanel(eqState: _eqState),
                  ],
                ),
              ),

              // Right: Headphone Library Sidebar (Animated Sliding Drawer)
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                width: _isSidebarOpen ? 280.0 : 0.0,
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.borderSubtle)),
                ),
                child: ClipRect(
                  child: OverflowBox(
                    minWidth: 280.0,
                    maxWidth: 280.0,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 280.0,
                      child: Sidebar(eqState: _eqState),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContextChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    bool showPulseDot = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: isActive ? AppColors.card : AppColors.inputBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? AppColors.borderHover : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPulseDot) ...[
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Transform.scale(
                    scale: isActive ? _pulseScale.value : 1.0,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.emerald.withValues(alpha: _pulseOpacity.value)
                            : AppColors.textMuted,
                        shape: BoxShape.circle,
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: AppColors.emeraldGlow.withValues(alpha: _pulseOpacity.value * 0.7),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              icon,
              size: 13,
              color: isActive ? activeColor : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                  color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
