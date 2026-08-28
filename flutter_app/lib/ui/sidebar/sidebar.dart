import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final List<HeadphoneModel> _models = [];
  List<HeadphoneModel> _allModelsCache = [];

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  void _loadModels() {
    // Note: in a real app, dbPath should be provided dynamically
    _allModelsCache = getHeadphoneModels(dbPath: 'ulteq.db');
  }

  Future<void> _showModelSelectionDialog(String type) async {
    final filteredModels = _allModelsCache.where((m) => m.formFactor == type).toList();
    
    final selectedModel = await showDialog<HeadphoneModel>(
      context: context,
      builder: (context) {
        return _ModelSelectionDialog(models: filteredModels, type: type);
      }
    );
    
    if (selectedModel != null) {
      setState(() {
        _models.add(selectedModel);
      });
    }
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
              onPressed: () => Navigator.pop(context, 'In-Ear'),
              child: const Text('In-Ear (IE)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'Over-Ear'),
              child: const Text('Over-Ear (OE)'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _showModelSelectionDialog(result);
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
                  title: Text('${model.brand} ${model.model}'),
                  subtitle: Text('Type: ${model.formFactor ?? "N/A"}\nRig: ${model.rig ?? "Unknown"}'),
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

class _ModelSelectionDialog extends StatefulWidget {
  final List<HeadphoneModel> models;
  final String type;

  const _ModelSelectionDialog({required this.models, required this.type});

  @override
  State<_ModelSelectionDialog> createState() => _ModelSelectionDialogState();
}

class _ModelSelectionDialogState extends State<_ModelSelectionDialog> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.models.where((m) {
      final text = '${m.brand} ${m.model}'.toLowerCase();
      return text.contains(_searchQuery.toLowerCase());
    }).toList();

    return AlertDialog(
      title: Text('Select ${widget.type} Headphone'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final m = filtered[index];
                  return ListTile(
                    title: Text('${m.brand} ${m.model}'),
                    subtitle: Text('Rig: ${m.rig ?? "Unknown"}'),
                    onTap: () {
                      Navigator.pop(context, m);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
