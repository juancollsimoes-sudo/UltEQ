import 'package:flutter/material.dart';
import '../../src/rust/api/simple.dart';
import '../../models/eq_state.dart';
import '../theme/app_theme.dart';

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
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  void _loadModels() {
    _allModelsCache = getHeadphoneModels(dbPath: 'ulteq.db');
  }

  Future<void> _showModelSelectionDialog(String? initialFormFactor) async {
    final selectedModel = await showDialog<HeadphoneModel>(
      context: context,
      builder: (context) {
        return _ModelSelectionDialog(
          models: _allModelsCache,
          initialFormFactor: initialFormFactor,
        );
      },
    );

    if (selectedModel != null) {
      widget.eqState.loadHeadphone(selectedModel);
      setState(() {
        final existingIdx = _models.indexWhere(
          (m) => m.brand == selectedModel.brand && m.model == selectedModel.model,
        );
        if (existingIdx != -1) {
          _activeIndex = existingIdx;
        } else {
          _models.add(selectedModel);
          _activeIndex = _models.length - 1;
        }
      });
    }
  }

  Future<void> _showImportCsvDialog() async {
    final textController = TextEditingController();
    final nameController = TextEditingController(text: 'Blessing 2 (Dual L/R)');

    const sampleBlessing2 = '''frequency,raw_l,raw_r
20.0,3.5,3.3
50.0,4.2,4.0
100.0,3.8,3.6
200.0,2.1,2.0
500.0,0.5,0.4
1000.0,0.0,0.0
2000.0,4.2,2.2
3000.0,9.5,7.0
4000.0,6.8,4.5
5000.0,4.2,2.1
6000.0,5.9,7.5
8000.0,8.0,8.2
10000.0,4.5,4.0
20000.0,-2.0,-2.5''';

    const sampleHexa = '''frequency,left,right
20.0,2.8,2.7
60.0,3.2,3.1
150.0,2.0,1.9
400.0,0.4,0.3
1000.0,0.0,0.0
2400.0,6.5,4.8
3500.0,8.2,6.4
4800.0,3.5,5.2
7000.0,6.2,6.3
10000.0,2.0,1.8
18000.0,-4.0,-4.5''';

    textController.text = sampleBlessing2;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: AppColors.surfaceRaised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.borderSubtle),
              ),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.file_upload_outlined, size: 18, color: AppColors.cyanLight),
                        const SizedBox(width: 8),
                        const Text(
                          'Import CSV Measurement (Dual-Channel / REW)',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
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
                    const SizedBox(height: 12),
                    const Text(
                      'Paste raw measurement CSV from REW, Squiglink, or Crinacle. Multi-column stereo headers supported (e.g. frequency, raw_l, raw_r):',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    // Presets Demo Bar
                    Row(
                      children: [
                        const Text('Presets Demo:', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            setDialogState(() {
                              nameController.text = 'Blessing 2 (Dual L/R)';
                              textController.text = sampleBlessing2;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.inputBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: const Text('Blessing 2 (L/R)', style: TextStyle(fontSize: 10.5, color: AppColors.cyanLight)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            setDialogState(() {
                              nameController.text = 'Truthear Hexa (L/R)';
                              textController.text = sampleHexa;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.inputBg,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: const Text('Hexa (L/R)', style: TextStyle(fontSize: 10.5, color: AppColors.roseLight)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Model Name Input
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: TextField(
                        controller: nameController,
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Model Name...',
                          hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(bottom: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // CSV Text Area
                    Container(
                      height: 160,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: TextField(
                        controller: textController,
                        maxLines: null,
                        expands: true,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: AppTypography.monoFont,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'frequency,raw_l,raw_r\n20.0,3.5,3.3\n...',
                          hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          onPressed: () {
                            if (textController.text.trim().isNotEmpty) {
                              final name = nameController.text.trim().isNotEmpty
                                  ? nameController.text.trim()
                                  : 'Custom Import';
                              widget.eqState.loadCustomCsv(textController.text, name);
                              final customModel = HeadphoneModel(
                                brand: 'Custom Import',
                                model: name,
                                formFactor: widget.eqState.isDualChannel ? 'Dual-Channel' : 'Single-Channel',
                              );
                              setState(() {
                                _models.add(customModel);
                                _activeIndex = _models.length - 1;
                              });
                              Navigator.pop(context);
                            }
                          },
                          child: const Text('Load Measurement'),
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
  }

  @override
  Widget build(BuildContext context) {
    final filteredLoadedModels = _models.where((m) {
      if (_filterQuery.isEmpty) return true;
      final query = _filterQuery.toLowerCase();
      return m.brand.toLowerCase().contains(query) || m.model.toLowerCase().contains(query);
    }).toList();

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Sidebar Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const Text('HEADPHONES', style: AppTypography.sectionHeader),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _models.isNotEmpty ? AppColors.primaryGlow : AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_models.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppTypography.monoFont,
                      color: _models.isNotEmpty ? AppColors.primaryLight : AppColors.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Import CSV Measurement (Dual-Channel / REW)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _showImportCsvDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_upload_outlined, size: 12, color: AppColors.cyanLight),
                          SizedBox(width: 4),
                          Text(
                            'Import',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showModelSelectionDialog(null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick Filter in Sidebar if more than 3 models
          if (_models.length > 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Filter loaded...',
                          hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) => setState(() => _filterQuery = val),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // List of Loaded Headphone Cards
          Expanded(
            child: _models.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.headphones_outlined, size: 36, color: AppColors.textMuted.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          const Text(
                            'No Headphones Loaded',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Click + Add to browse measurements from Crinacle, Oratory, and Rtings',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: filteredLoadedModels.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final model = filteredLoadedModels[index];
                      final originalIndex = _models.indexOf(model);
                      final isActive = _activeIndex == originalIndex;

                      final isIEM = (model.formFactor ?? '').toLowerCase().contains('in-ear') ||
                          model.formFactor == 'ie';

                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            if (_activeIndex == originalIndex) {
                              _activeIndex = null;
                              widget.eqState.clearHeadphone();
                            } else {
                              _activeIndex = originalIndex;
                              widget.eqState.loadHeadphone(model);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(10),
                          decoration: AppDecorations.card(isSelected: isActive),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // Active Indicator Dot
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: isActive ? AppColors.emerald : AppColors.borderSubtle,
                                      shape: BoxShape.circle,
                                      boxShadow: isActive
                                          ? [const BoxShadow(color: AppColors.emeraldGlow, blurRadius: 6)]
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Brand & Model
                                  Expanded(
                                    child: Text(
                                      '${model.brand} ${model.model}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                                        color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // Remove Button
                                  InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      setState(() {
                                        _models.removeAt(originalIndex);
                                        if (_activeIndex == originalIndex) {
                                          _activeIndex = null;
                                          widget.eqState.clearHeadphone();
                                        } else if (_activeIndex != null && _activeIndex! > originalIndex) {
                                          _activeIndex = _activeIndex! - 1;
                                        }
                                      });
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(2.0),
                                      child: Icon(Icons.close, size: 13, color: AppColors.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              // Pills: Form Factor + Measurement Rig
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: isIEM ? AppColors.cyan.withOpacity(0.12) : AppColors.primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isIEM ? 'In-Ear' : 'Over-Ear',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: isIEM ? AppColors.cyanLight : AppColors.primaryLight,
                                      ),
                                    ),
                                  ),
                                  if (isActive && widget.eqState.isDualChannel) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [AppColors.cyan, AppColors.rose],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'L/R Dual',
                                        style: TextStyle(
                                          fontSize: 9.0,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                                  if (model.rig != null && model.rig!.isNotEmpty)
                                    Expanded(
                                      child: Text(
                                        model.rig!,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontFamily: AppTypography.monoFont,
                                          color: AppColors.textMuted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
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
  final String? initialFormFactor;

  const _ModelSelectionDialog({
    required this.models,
    this.initialFormFactor,
  });

  @override
  State<_ModelSelectionDialog> createState() => _ModelSelectionDialogState();
}

class _ModelSelectionDialogState extends State<_ModelSelectionDialog> {
  String _searchQuery = '';
  String _selectedTab = 'All'; // 'All', 'In-Ear', 'Over-Ear'

  @override
  void initState() {
    super.initState();
    if (widget.initialFormFactor != null) {
      final ff = widget.initialFormFactor!.toLowerCase();
      if (ff.contains('in-ear') || ff == 'ie') {
        _selectedTab = 'In-Ear';
      } else if (ff.contains('over-ear') || ff == 'oe') {
        _selectedTab = 'Over-Ear';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.models.where((m) {
      // Tab filter
      if (_selectedTab == 'In-Ear') {
        final ff = (m.formFactor ?? '').toLowerCase();
        if (!ff.contains('in-ear') && ff != 'ie') return false;
      } else if (_selectedTab == 'Over-Ear') {
        final ff = (m.formFactor ?? '').toLowerCase();
        if (!ff.contains('over-ear') && ff != 'oe') return false;
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final text = '${m.brand} ${m.model} ${m.rig ?? ""}'.toLowerCase();
        return text.contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      final brandCmp = a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
      if (brandCmp != 0) return brandCmp;
      return a.model.toLowerCase().compareTo(b.model.toLowerCase());
    });

    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
      child: Container(
        width: 580,
        height: 520,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Close
            Row(
              children: [
                const Icon(Icons.search, size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 8),
                const Text(
                  'Select Headphone Measurement',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
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
            const SizedBox(height: 14),

            // Search Bar & Segmented Tabs
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 15, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            autofocus: true,
                            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Search brand, model, or rig...',
                              hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                              border: InputBorder.none,
                              isDense: true,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          InkWell(
                            onTap: () => setState(() => _searchQuery = ''),
                            child: const Icon(Icons.clear, size: 14, color: AppColors.textMuted),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Form Factor Filter Pills
                _buildTabPill('All'),
                const SizedBox(width: 4),
                _buildTabPill('In-Ear'),
                const SizedBox(width: 4),
                _buildTabPill('Over-Ear'),
              ],
            ),
            const SizedBox(height: 12),

            // Results Counter
            Text(
              '${filtered.length} measurements found',
              style: AppTypography.monoSmall,
            ),
            const SizedBox(height: 8),

            // Results List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matching measurements found for "$_searchQuery"',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.borderSubtle),
                      itemBuilder: (context, index) {
                        final m = filtered[index];
                        final isIEM = (m.formFactor ?? '').toLowerCase().contains('in-ear') || m.formFactor == 'ie';

                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: AppColors.cardHover,
                          onTap: () => Navigator.pop(context, m),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${m.brand} ${m.model}',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Rig: ${m.rig ?? "Standard"}',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontFamily: AppTypography.monoFont,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isIEM ? AppColors.cyan.withOpacity(0.12) : AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isIEM ? AppColors.cyanLight.withOpacity(0.3) : AppColors.primaryLight.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    isIEM ? 'In-Ear' : 'Over-Ear',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isIEM ? AppColors.cyanLight : AppColors.primaryLight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill(String title) {
    final isSelected = _selectedTab == title;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() => _selectedTab = title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
