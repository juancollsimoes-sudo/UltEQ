import 'package:flutter/material.dart';
import '../../models/eq_state.dart';
import '../theme/app_theme.dart';

class BandListPanel extends StatelessWidget {
  final EqState eqState;

  const BandListPanel({super.key, required this.eqState});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Panel Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const Text('FILTERS', style: AppTypography.sectionHeader),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: eqState,
                  builder: (context, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: eqState.nodes.isNotEmpty
                            ? AppColors.primaryGlow
                            : AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${eqState.nodes.length} / 10',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppTypography.monoFont,
                          color: eqState.nodes.isNotEmpty
                              ? AppColors.primaryLight
                              : AppColors.textMuted,
                        ),
                      ),
                    );
                  },
                ),
                const Spacer(),
                // Add Band Button
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    if (eqState.nodes.length < 10) {
                      eqState.addNode(EqNode(freq: 1000.0, gain: 0.0, q: 1.414));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: AppColors.primaryLight),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Clear All Button
                ListenableBuilder(
                  listenable: eqState,
                  builder: (context, _) {
                    if (eqState.nodes.isEmpty) return const SizedBox.shrink();
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => eqState.clearNodes(),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: const Icon(Icons.delete_sweep_outlined, size: 14, color: AppColors.textMuted),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Band Cards List
          Expanded(
            child: ListenableBuilder(
              listenable: eqState,
              builder: (context, _) {
                if (eqState.nodes.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.graphic_eq, size: 36, color: AppColors.textMuted.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          const Text(
                            'No Active Filters',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Double-click the canvas or click AutoEq to generate filters',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemCount: eqState.nodes.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final node = eqState.nodes[index];
                    final isSelected = eqState.selectedIndex == index;

                    Color typeColor;
                    String typeStr;
                    switch (node.type) {
                      case EqFilterType.lowShelf:
                        typeColor = AppColors.cyanLight;
                        typeStr = 'Low Shelf';
                        break;
                      case EqFilterType.highShelf:
                        typeColor = AppColors.amberLight;
                        typeStr = 'High Shelf';
                        break;
                      case EqFilterType.peaking:
                        typeColor = AppColors.primaryLight;
                        typeStr = 'Peaking';
                        break;
                    }

                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => eqState.selectNode(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.all(10),
                        decoration: AppDecorations.card(isSelected: isSelected),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Card Header: Badge, Type Dropdown, Delete
                            Row(
                              children: [
                                // Index Pill
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(alpha: 0.2)
                                        : AppColors.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primaryLight.withValues(alpha: 0.4)
                                          : AppColors.borderSubtle,
                                    ),
                                  ),
                                  child: Text(
                                    'B${index + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: AppTypography.monoFont,
                                      color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Filter Type Dropdown
                                _buildFilterTypeDropdown(node, typeColor, typeStr),
                                const Spacer(),
                                // Delete Action
                                InkWell(
                                  borderRadius: BorderRadius.circular(4),
                                  onTap: () => eqState.removeNode(index),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3.0),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: isSelected ? AppColors.rose : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Parameter Inputs Grid
                            Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _CompactParamField(
                                    label: 'Hz',
                                    value: node.freq,
                                    decimals: node.freq >= 1000 ? 0 : 0,
                                    min: 20.0,
                                    max: 20000.0,
                                    onChanged: (val) {
                                      node.freq = val.clamp(20.0, 20000.0);
                                      eqState.triggerUpdate();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 4,
                                  child: _CompactParamField(
                                    label: 'dB',
                                    value: node.gain,
                                    decimals: 1,
                                    min: -15.0,
                                    max: 15.0,
                                    prefix: node.gain >= 0 ? '+' : '',
                                    onChanged: (val) {
                                      node.gain = val.clamp(-15.0, 15.0);
                                      eqState.triggerUpdate();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 4,
                                  child: _CompactParamField(
                                    label: 'Q',
                                    value: node.q,
                                    decimals: 2,
                                    min: 0.1,
                                    max: 10.0,
                                    onChanged: (val) {
                                      node.q = val.clamp(0.1, 10.0);
                                      eqState.triggerUpdate();
                                    },
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTypeDropdown(EqNode node, Color typeColor, String typeStr) {
    return PopupMenuButton<EqFilterType>(
      initialValue: node.type,
      tooltip: 'Change Filter Type',
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
      onSelected: (newType) {
        node.type = newType;
        eqState.triggerUpdate();
      },
      itemBuilder: (context) => [
        _buildPopupMenuItem(EqFilterType.peaking, 'Peaking (PK)', AppColors.primaryLight),
        _buildPopupMenuItem(EqFilterType.lowShelf, 'Low Shelf (LS)', AppColors.cyanLight),
        _buildPopupMenuItem(EqFilterType.highShelf, 'High Shelf (HS)', AppColors.amberLight),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: typeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: typeColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              typeStr,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: typeColor,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down, size: 14, color: typeColor),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<EqFilterType> _buildPopupMenuItem(
    EqFilterType type,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: type,
      height: 32,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _CompactParamField extends StatefulWidget {
  final String label;
  final double value;
  final int decimals;
  final double min;
  final double max;
  final String prefix;
  final Function(double) onChanged;

  const _CompactParamField({
    required this.label,
    required this.value,
    this.decimals = 1,
    required this.min,
    required this.max,
    this.prefix = '',
    required this.onChanged,
  });

  @override
  State<_CompactParamField> createState() => _CompactParamFieldState();
}

class _CompactParamFieldState extends State<_CompactParamField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (!_focusNode.hasFocus) {
        final parsed = double.tryParse(_controller.text);
        if (parsed != null) {
          widget.onChanged(parsed.clamp(widget.min, widget.max));
        }
        _controller.text = _format(widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CompactParamField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _format(double val) {
    return val.toStringAsFixed(widget.decimals);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _isFocused ? AppColors.borderActive : AppColors.borderSubtle,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: AppTypography.monoFont,
                color: AppColors.textPrimary,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null) {
                  widget.onChanged(parsed.clamp(widget.min, widget.max));
                }
              },
            ),
          ),
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 9,
              fontFamily: AppTypography.monoFont,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
