import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/eq_state.dart';
import '../../src/rust/api/simple.dart';
import '../theme/app_theme.dart';

enum ExportFormat {
  equalizerApo,
  qudelix,
  wavelet,
  roon,
}

class ExportPresetDialog extends StatefulWidget {
  final EqState eqState;

  const ExportPresetDialog({super.key, required this.eqState});

  @override
  State<ExportPresetDialog> createState() => _ExportPresetDialogState();
}

class _ExportPresetDialogState extends State<ExportPresetDialog> {
  ExportFormat _selectedFormat = ExportFormat.equalizerApo;
  bool _isCopied = false;
  String? _savedFilePath;

  List<ActiveFilter> _getGlobalFilters() {
    return widget.eqState.nodes.map((n) {
      FilterType t = FilterType.peaking;
      if (n.type == EqFilterType.lowShelf) t = FilterType.lowShelf;
      if (n.type == EqFilterType.highShelf) t = FilterType.highShelf;
      return ActiveFilter(
        filterType: t,
        freq: n.freq,
        gain: n.gain,
        q: n.q,
      );
    }).toList();
  }

  String _generateExportContent() {
    final globalFilters = _getGlobalFilters();
    final preamp = widget.eqState.preampGain;

    switch (_selectedFormat) {
      case ExportFormat.equalizerApo:
        final bool isStereo = widget.eqState.matchChannels &&
            widget.eqState.channelMatchFiltersL.isNotEmpty;
        final leftFilters = isStereo
            ? [...widget.eqState.channelMatchFiltersL, ...globalFilters]
            : globalFilters;
        final rightFilters = isStereo
            ? [...widget.eqState.channelMatchFiltersR, ...globalFilters]
            : <ActiveFilter>[];

        return exportPresetEqualizerApo(
          leftFilters: leftFilters,
          rightFilters: rightFilters,
          preamp: preamp,
        );

      case ExportFormat.qudelix:
        return exportPresetQudelix(
          filters: globalFilters,
          preamp: preamp,
        );

      case ExportFormat.wavelet:
        return exportPresetWavelet(
          filters: globalFilters,
        );

      case ExportFormat.roon:
        return exportPresetRoon(
          filters: globalFilters,
          preamp: preamp,
        );
    }
  }

  String _getFileExtension() {
    switch (_selectedFormat) {
      case ExportFormat.roon:
        return 'json';
      case ExportFormat.equalizerApo:
      case ExportFormat.qudelix:
      case ExportFormat.wavelet:
        return 'txt';
    }
  }

  String _getFormatLabel(ExportFormat format) {
    switch (format) {
      case ExportFormat.equalizerApo:
        return 'Peace / Equalizer APO';
      case ExportFormat.qudelix:
        return 'Qudelix 5K / FiiO';
      case ExportFormat.wavelet:
        return 'Wavelet GraphicEQ';
      case ExportFormat.roon:
        return 'Roon DSP';
    }
  }

  String _getSuggestedFileName() {
    final hp = widget.eqState.activeHeadphone;
    final base = hp != null
        ? '${hp.brand}_${hp.model}'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        : 'ulteq_preset';
    final formatSuffix = _selectedFormat.name;
    final ext = _getFileExtension();
    return '${base}_$formatSuffix.$ext';
  }

  Future<void> _copyToClipboard(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      setState(() => _isCopied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
  }

  Future<void> _saveToFile(String content) async {
    final fileName = _getSuggestedFileName();
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    
    // Prefer Downloads or current dir
    final downloadsDir = Directory('$home/Downloads');
    final targetDir = downloadsDir.existsSync() ? downloadsDir.path : home;
    final savePath = '$targetDir/$fileName';

    try {
      final file = File(savePath);
      await file.writeAsString(content);
      if (mounted) {
        setState(() => _savedFilePath = savePath);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _savedFilePath = null);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: AppColors.rose,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _generateExportContent();
    final ext = _getFileExtension();

    return Dialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
      child: Container(
        width: 640,
        height: 560,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primaryLight.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(Icons.download, size: 18, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Universal Preset Export',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Export DSP parametric filters and targets for external hardware & players',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
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

            const SizedBox(height: 18),

            // Format Selection Tabs
            Container(
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: ExportFormat.values.map((format) {
                  final isSelected = _selectedFormat == format;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          _selectedFormat = format;
                          _isCopied = false;
                          _savedFilePath = null;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.surfaceRaised : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: isSelected
                              ? Border.all(color: AppColors.borderSubtle)
                              : null,
                          boxShadow: isSelected
                              ? const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _getFormatLabel(format),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 14),

            // Content Preview Header & Stats
            Row(
              children: [
                Text(
                  'PREVIEW (.${ext.toUpperCase()})',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Text(
                    '${widget.eqState.nodes.length} Bands  •  Preamp ${widget.eqState.preampGain.toStringAsFixed(1)} dB',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontFamily: AppTypography.monoFont,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const Spacer(),
                if (_savedFilePath != null)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Icon(Icons.check_circle, size: 13, color: AppColors.emerald),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Saved: ${_savedFilePath!.split('/').last}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.emeraldLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Monospace Code Container
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.canvasBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content,
                    style: const TextStyle(
                      fontFamily: AppTypography.monoFont,
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action Footer
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 14, color: AppColors.textMuted),
                  label: const Text('Refresh', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  onPressed: () => setState(() {}),
                ),
                const Spacer(),
                // Copy to Clipboard
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isCopied ? AppColors.emerald : AppColors.card,
                    foregroundColor: _isCopied ? Colors.white : AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: _isCopied
                            ? AppColors.emeraldLight
                            : AppColors.borderSubtle,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: Icon(
                    _isCopied ? Icons.check : Icons.copy,
                    size: 14,
                    color: _isCopied ? Colors.white : AppColors.textSecondary,
                  ),
                  label: Text(
                    _isCopied ? 'Copied to Clipboard!' : 'Copy to Clipboard',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _copyToClipboard(content),
                ),

                const SizedBox(width: 10),

                // Save as File
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.save_alt, size: 14),
                  label: Text(
                    'Save as .$ext',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _saveToFile(content),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
