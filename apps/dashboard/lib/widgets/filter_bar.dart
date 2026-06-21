import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DaysFilter extends StatelessWidget {
  const DaysFilter({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const options = [1, 7, 14, 30, 90];
  static const labels = {1: '24h', 7: '7d', 14: '14d', 30: '30d', 90: '90d'};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 420) {
        return SizedBox(
          width: c.maxWidth.isFinite ? c.maxWidth : double.infinity,
          child: DropdownButtonFormField<int>(
            value: value,
            isExpanded: true,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            items: [for (final d in options) DropdownMenuItem(value: d, child: Text(labels[d]!, style: const TextStyle(fontSize: 13)))],
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<int>(
          segments: [for (final d in options) ButtonSegment(value: d, label: Text(labels[d]!))],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
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
  const TypeFilterRow({super.key, required this.options, required this.selected, required this.onSelected});

  final List<String?> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((t) {
        final label = switch (t) {
          null => 'All',
          'errors' => 'Errors',
          String type => type,
        };
        return FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          visualDensity: VisualDensity.compact,
          selected: selected == t,
          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
          checkmarkColor: AppTheme.primary,
          onSelected: (_) => onSelected(t),
        );
      }).toList(),
    );
  }
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    this.days,
    this.onDaysChanged,
    this.searchHint,
    this.searchValue,
    this.onSearch,
    this.typeOptions,
    this.typeSelected,
    this.onTypeSelected,
    this.extra,
  });

  final int? days;
  final ValueChanged<int>? onDaysChanged;
  final String? searchHint;
  final String? searchValue;
  final ValueChanged<String>? onSearch;
  final List<String?>? typeOptions;
  final String? typeSelected;
  final ValueChanged<String?>? onTypeSelected;
  final List<Widget>? extra;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final children = <Widget>[
      if (days != null && onDaysChanged != null) DaysFilter(value: days!, onChanged: onDaysChanged!),
      if (searchHint != null && onSearch != null) SearchField(hint: searchHint!, initialValue: searchValue, onSubmitted: onSearch!),
      if (typeOptions != null && onTypeSelected != null) TypeFilterRow(options: typeOptions!, selected: typeSelected, onSelected: onTypeSelected!),
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

String periodLabel(int days) => days == 1 ? 'today' : 'last $days days';
