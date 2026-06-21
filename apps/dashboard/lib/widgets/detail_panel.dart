import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (trailing != null) ...[const Spacer(), trailing!],
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.mono = false, this.onCopy});

  final String label;
  final String value;
  final bool mono;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == '—') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: mono ? 'monospace' : null),
          ),
        ),
        if (onCopy != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 16),
            onPressed: onCopy,
            tooltip: 'Copy',
          ),
      ]),
    );
  }
}

class FlowStrip extends StatelessWidget {
  const FlowStrip({super.key, required this.items, this.embedded = false});

  final List<FlowItem> items;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((i) => i.value.isNotEmpty && i.value != '—').toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final inner = LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 560) {
        return Column(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.arrow_downward, size: 14, color: AppTheme.muted)),
              _FlowTile(item: visible[i]),
            ],
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 16, color: AppTheme.muted)),
            Expanded(child: _FlowTile(item: visible[i])),
          ],
        ],
      );
    });

    if (embedded) {
      return Padding(padding: const EdgeInsets.all(10), child: inner);
    }
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: inner));
  }
}

class FlowItem {
  const FlowItem(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({required this.item});
  final FlowItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(item.icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(item.label, style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(item.value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

class CodePanel extends StatelessWidget {
  const CodePanel({super.key, required this.title, required this.code, this.maxHeight = 320});

  final String title;
  final String code;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (code.trim().isEmpty) return const SizedBox.shrink();
    return DetailSection(
      title: title,
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        tooltip: 'Copy',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title copied')));
        },
      ),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFE2E8F0), height: 1.5)),
        ),
      ),
    );
  }
}
