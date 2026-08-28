import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';
import '../../models/eq_state.dart';

class Sidebar extends StatefulWidget {
  final EqState eqState;
  const Sidebar({super.key, required this.eqState});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final List<HeadphoneModel> _models = [];
  List<HeadphoneModel> _allModelsCache = [];
  int? _activeIndex;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  void _loadModels() {
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
      widget.eqState.loadHeadphone(selectedModel);
      setState(() {
        _models.add(selectedModel);
        _activeIndex = _models.length - 1;
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
              onPressed: () => Navigator.pop(context, 'in-ear'),
              child: const Text('In-Ear (IE)'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'over-ear'),
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
                final isActive = _activeIndex == index;
                return Container(
                  color: isActive ? Colors.white24 : Colors.transparent,
                  child: ListTile(
                    title: Text('${model.brand} ${model.model}'),
                    subtitle: Text('Type: ${model.formFactor ?? "N/A"}\nRig: ${model.rig ?? "Unknown"}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          _models.removeAt(index);
                          if (_activeIndex == index) {
                            _activeIndex = null;
                            widget.eqState.clearHeadphone();
                          } else if (_activeIndex != null && _activeIndex! > index) {
                            _activeIndex = _activeIndex! - 1;
                          }
                        });
                      },
                    ),
                    onTap: () {
                      setState(() {
                        if (_activeIndex == index) {
                          _activeIndex = null;
                          widget.eqState.clearHeadphone();
                        } else {
                          _activeIndex = index;
                          widget.eqState.loadHeadphone(model);
                        }
                      });
                    },
                  ),
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

    filtered.sort((a, b) => (a.rig ?? 'Unknown').compareTo(b.rig ?? 'Unknown'));

    final listItems = [];
    String? currentRig;
    for (final m in filtered) {
      final rig = m.rig ?? 'Unknown';
      if (rig != currentRig) {
        listItems.add(rig);
        currentRig = rig;
      }
      listItems.add(m);
    }

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
                itemCount: listItems.length,
                itemBuilder: (context, index) {
                  final item = listItems[index];
                  if (item is String) {
                    return Container(
                      color: Colors.white10,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(item, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan)),
                    );
                  }
                  final m = item as HeadphoneModel;
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
