import 'package:flutter/material.dart';
import '../../models/eq_state.dart';

class BandListPanel extends StatelessWidget {
  final EqState eqState;

  const BandListPanel({super.key, required this.eqState});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16191E),
      padding: const EdgeInsets.all(8.0),
      child: ListenableBuilder(
        listenable: eqState,
        builder: (context, _) {
          if (eqState.nodes.isEmpty) {
            return const Center(
              child: Text(
                'No bands added. Right-click on canvas to add a band.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            itemCount: eqState.nodes.length,
            itemBuilder: (context, index) {
              final node = eqState.nodes[index];
              final isSelected = eqState.selectedIndex == index;

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4.0),
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withOpacity(0.1) : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? Colors.white38 : Colors.white12,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Text('Band ${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 16),
                    _buildTextField(
                      label: 'Freq',
                      value: node.freq,
                      onChanged: (val) {
                        node.freq = val.clamp(20.0, 20000.0);
                        eqState.triggerUpdate();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildTextField(
                      label: 'Gain',
                      value: node.gain,
                      onChanged: (val) {
                        node.gain = val.clamp(-15.0, 15.0);
                        eqState.triggerUpdate();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildTextField(
                      label: 'Q',
                      value: node.q,
                      onChanged: (val) {
                        node.q = val.clamp(0.1, 10.0);
                        eqState.triggerUpdate();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildDropdown(
                      value: node.type,
                      onChanged: (newType) {
                        if (newType != null) {
                          node.type = newType;
                          eqState.triggerUpdate();
                        }
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                      onPressed: () {
                        eqState.removeNode(index);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required double value,
    required Function(double) onChanged,
  }) {
    // We use a separate stateful widget to handle local editing state
    // so we don't lose focus or mess up the cursor when the parent rebuilds.
    return _DebouncedNumericField(
      label: label,
      initialValue: value,
      onChanged: onChanged,
    );
  }

  Widget _buildDropdown({
    required EqFilterType value,
    required Function(EqFilterType?) onChanged,
  }) {
    return SizedBox(
      height: 32,
      child: DropdownButton<EqFilterType>(
        value: value,
        dropdownColor: const Color(0xFF16191E),
        style: const TextStyle(fontSize: 12, color: Colors.white),
        underline: Container(height: 1, color: Colors.white24),
        items: const [
          DropdownMenuItem(value: EqFilterType.peaking, child: Text('PK')),
          DropdownMenuItem(value: EqFilterType.lowShelf, child: Text('LS')),
          DropdownMenuItem(value: EqFilterType.highShelf, child: Text('HS')),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DebouncedNumericField extends StatefulWidget {
  final String label;
  final double initialValue;
  final Function(double) onChanged;

  const _DebouncedNumericField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_DebouncedNumericField> createState() => _DebouncedNumericFieldState();
}

class _DebouncedNumericFieldState extends State<_DebouncedNumericField> {
  late TextEditingController _controller;
  double _lastValidValue = 0;

  @override
  void initState() {
    super.initState();
    _lastValidValue = widget.initialValue;
    _controller = TextEditingController(text: _format(widget.initialValue));
  }

  @override
  void didUpdateWidget(covariant _DebouncedNumericField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _lastValidValue) {
      _lastValidValue = widget.initialValue;
      final newText = _format(widget.initialValue);
      if (_controller.text != newText && !FocusScope.of(context).hasFocus) {
         _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _format(double val) {
    return val.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 32,
      child: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: 12),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(fontSize: 10, color: Colors.white70),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (val) {
          final parsed = double.tryParse(val);
          if (parsed != null) {
            _lastValidValue = parsed;
            widget.onChanged(parsed);
          }
        },
      ),
    );
  }
}
