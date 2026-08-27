import 'package:flutter/material.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final List<Map<String, String>> _models = [];

  void _addModel(String type) {
    setState(() {
      if (type == 'IE') {
        _models.add({
          'name': 'Moondrop Aria ($type)',
          'target': 'Harman IE 2019',
          'tool': 'B&K 5128',
        });
      } else {
        _models.add({
          'name': 'Sennheiser HD600 ($type)',
          'target': 'Harman OE 2018',
          'tool': 'GRAS 43AG',
        });
      }
    });
  }

  Future<void> _showAddDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Headphone'),
          content: const Text('Select type:'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'IE'),
              child: const Text('In-Ear (IE)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'OE'),
              child: const Text('Over-Ear (OE)'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      _addModel(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16191E),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Headphones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showAddDialog,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: _models.length,
              itemBuilder: (context, index) {
                final model = _models[index];
                return ListTile(
                  title: Text(model['name']!),
                  subtitle: Text('Target: ${model['target']!}\nTool: ${model['tool']!}'),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
