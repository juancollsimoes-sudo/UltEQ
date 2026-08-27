import 'package:flutter/material.dart';

class EqPanel extends StatelessWidget {
  const EqPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16191E),
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(10, (index) => _buildEqBand(index)),
      ),
    );
  }

  Widget _buildEqBand(int index) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Gain Slider
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: 0,
              min: -15,
              max: 15,
              onChanged: (value) {},
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Freq
        _buildSmallTextField('Freq', index == 0 ? '32' : '${32 * (1 << index)}'),
        const SizedBox(height: 4),
        // Q
        _buildSmallTextField('Q', '1.41'),
        const SizedBox(height: 4),
        // Filter Type
        _buildDropdown(),
      ],
    );
  }

  Widget _buildSmallTextField(String label, String initialValue) {
    return SizedBox(
      width: 40,
      height: 24,
      child: TextField(
        controller: TextEditingController(text: initialValue),
        style: const TextStyle(fontSize: 10),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return SizedBox(
      width: 45,
      height: 24,
      child: DropdownButton<String>(
        value: 'PK',
        isExpanded: true,
        style: const TextStyle(fontSize: 10),
        underline: const SizedBox(),
        items: const [
          DropdownMenuItem(value: 'PK', child: Text('PK')),
          DropdownMenuItem(value: 'LS', child: Text('LS')),
          DropdownMenuItem(value: 'HS', child: Text('HS')),
        ],
        onChanged: (value) {},
      ),
    );
  }
}
