import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_range.dart';
import 'period_picker.dart';

class PeriodFilterBar extends StatelessWidget {
  const PeriodFilterBar({super.key, required this.value, required this.onChanged});

  final PeriodFilter value;
  final ValueChanged<PeriodFilter> onChanged;

  static const presets = [1, 7, 14, 30, 90];
  static const labels = {1: '24h', 7: '7d', 14: '14d', 30: '30d', 90: '90d'};

  void _openPicker(BuildContext context) => showPeriodPicker(context, current: value, onSelected: onChanged);

  @override
  Widget build(BuildContext context) {
    final customSelected = value.isCustom;
    final customLabel = customSelected ? value.label() : 'Custom';

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 480) {
        return Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: value.isPreset ? value.days : null,
                isExpanded: true,
                decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                items: [
                  for (final d in presets) DropdownMenuItem(value: d, child: Text(labels[d]!, style: const TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: -1, child: Text(customSelected ? customLabel : 'Custom range…', style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  if (v == -1) {
                    _openPicker(context);
                  } else {
                    onChanged(PeriodFilter.days(v));
                  }
                },
              ),
            ),
          ],
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<int>(
              segments: [for (final d in presets) ButtonSegment(value: d, label: Text(labels[d]!))],
              selected: value.isPreset ? {value.days!} : {},
              onSelectionChanged: (s) => onChanged(PeriodFilter.days(s.first)),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _openPicker(context),
              icon: const Icon(Icons.calendar_month, size: 16),
              label: Text(customLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: customSelected ? AppTheme.primary.withValues(alpha: 0.1) : null,
                foregroundColor: customSelected ? AppTheme.primary : null,
                side: BorderSide(color: customSelected ? AppTheme.primary : AppTheme.border),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.hint, required this.onSubmitted, this.initialValue});

  final String hint;
  final ValueChanged<String> onSubmitted;
  final String? initialValue;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : double.infinity;
      return SizedBox(
        width: w,
        child: TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          onSubmitted: widget.onSubmitted,
        ),
      );
    });
  }
}

class TypeFilterRow extends StatelessWidget {
  const TypeFilterRow({super.key, required this.options, required this.selected, required this.onSelected, this.label});

  final String? label;
  final List<String?> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _defaultLabels = {
    null: 'All',
    'errors': 'Errors',
    'error': 'Error',
    'crash': 'Crash',
    'network': 'Network',
    'session': 'Session',
    'log': 'Log',
    'span': 'Span',
    'info': 'Info',
    'warning': 'Warning',
    'success': 'Success',
    'system': 'System',
    'crashing': 'Crashing',
    'logic': 'Logic',
    'ui': 'UI',
  };

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((t) {
        final chipLabel = _defaultLabels[t] ?? t!;
        return FilterChip(
          label: Text(chipLabel, style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          selected: selected == t,
          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
          checkmarkColor: AppTheme.primary,
          onSelected: (_) => onSelected(t),
        );
      }).toList(),
    );
    if (label == null) return chips;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.muted)),
        const SizedBox(height: 6),
        chips,
      ],
    );
  }
}

class FacetDropdown extends StatelessWidget {
  const FacetDropdown({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final safe = selected != null && options.contains(selected) ? selected : null;
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<String?>(
        value: safe,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All', style: TextStyle(fontSize: 13))),
          for (final o in options) DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onSelected,
      ),
    );
  }
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.period,
    this.onPeriodChanged,
    this.searchHint,
    this.searchValue,
    this.onSearch,
    this.typeOptions,
    this.typeSelected,
    this.onTypeSelected,
    this.levelOptions,
    this.levelSelected,
    this.onLevelSelected,
    this.categoryOptions,
    this.categorySelected,
    this.onCategorySelected,
    this.environmentOptions,
    this.environmentSelected,
    this.onEnvironmentSelected,
    this.appVersionOptions,
    this.appVersionSelected,
    this.onAppVersionSelected,
    this.deviceNameOptions,
    this.deviceNameSelected,
    this.onDeviceNameSelected,
    this.extra,
  });

  final PeriodFilter? period;
  final ValueChanged<PeriodFilter>? onPeriodChanged;
  final String? searchHint;
  final String? searchValue;
  final ValueChanged<String>? onSearch;
  final List<String?>? typeOptions;
  final String? typeSelected;
  final ValueChanged<String?>? onTypeSelected;
  final List<String?>? levelOptions;
  final String? levelSelected;
  final ValueChanged<String?>? onLevelSelected;
  final List<String?>? categoryOptions;
  final String? categorySelected;
  final ValueChanged<String?>? onCategorySelected;
  final List<String>? environmentOptions;
  final String? environmentSelected;
  final ValueChanged<String?>? onEnvironmentSelected;
  final List<String>? appVersionOptions;
  final String? appVersionSelected;
  final ValueChanged<String?>? onAppVersionSelected;
  final List<String>? deviceNameOptions;
  final String? deviceNameSelected;
  final ValueChanged<String?>? onDeviceNameSelected;
  final List<Widget>? extra;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final children = <Widget>[
      if (period != null && onPeriodChanged != null) PeriodFilterBar(value: period!, onChanged: onPeriodChanged!),
      if (searchHint != null && onSearch != null) SearchField(hint: searchHint!, initialValue: searchValue, onSubmitted: onSearch!),
      if (levelOptions != null && onLevelSelected != null)
        TypeFilterRow(label: 'Level', options: levelOptions!, selected: levelSelected, onSelected: onLevelSelected!),
      if (typeOptions != null && onTypeSelected != null)
        TypeFilterRow(label: 'Kind', options: typeOptions!, selected: typeSelected, onSelected: onTypeSelected!),
      if (categoryOptions != null && onCategorySelected != null)
        TypeFilterRow(label: 'Category', options: categoryOptions!, selected: categorySelected, onSelected: onCategorySelected!),
      if (environmentOptions != null && onEnvironmentSelected != null)
        FacetDropdown(label: 'Environment', options: environmentOptions!, selected: environmentSelected, onSelected: onEnvironmentSelected!),
      if (appVersionOptions != null && onAppVersionSelected != null)
        FacetDropdown(label: 'App version', options: appVersionOptions!, selected: appVersionSelected, onSelected: onAppVersionSelected!),
      if (deviceNameOptions != null && onDeviceNameSelected != null)
        FacetDropdown(label: 'Device', options: deviceNameOptions!, selected: deviceNameSelected, onSelected: onDeviceNameSelected!),
      if (extra != null) ...extra!,
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      padding: EdgeInsets.all(narrow ? 10 : 12),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 10), children[i]]])
          : Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children),
    );
  }
}
