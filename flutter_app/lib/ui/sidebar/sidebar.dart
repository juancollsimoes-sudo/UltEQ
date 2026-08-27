import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final List<HeadphoneModel> _models = [];

  void _addModel(String type) {
    setState(() {
      final allModels = getModels();
      final model = allModels.firstWhere(
        (m) => m.modelType == type,
        orElse: () => allModels.first,
      );
      _models.add(model);
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
                  title: Text(model.name),
                  subtitle: Text('Target: ${model.defaultTarget}\nTool: ${model.tool}'),
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
