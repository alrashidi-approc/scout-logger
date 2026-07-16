import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:scout_models/scout_models.dart';

import '../services/api_client.dart';
import '../services/dashboard_log_service.dart';
import '../services/screen_cache.dart';
import '../utils/date_range.dart';
import '../utils/report_pdf.dart';
import '../utils/responsive.dart';
import '../utils/screen_load.dart';
import '../widgets/filter_bar.dart';
import '../widgets/page_header.dart';
import '../widgets/period_picker.dart';
import '../widgets/shared_report_view.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.projectId, this.initialPeriod = const PeriodFilter.days(30)});

  final String projectId;
  final PeriodFilter initialPeriod;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _api = ScoutApi();
  ReportType _type = ReportType.executiveSummary;
  ReportAudience _audience = ReportAudience.engineering;
  Report? _report;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasData = false;
  bool _exporting = false;
  Object? _error;
  late PeriodFilter _period = widget.initialPeriod;

  String get _cacheKey => screenCacheKey(
        'reports',
        projectId: widget.projectId,
        period: _period,
        extra: {'type': _type.id, 'audience': _audience.id},
      );

  @override
  void initState() {
    super.initState();
    if (!_restore()) _load();
  }

  bool _restore() {
    final cached = ScreenCache.instance.read<Report>(_cacheKey);
    if (cached == null) return false;
    _report = cached;
    _hasData = true;
    _loading = false;
    _refreshing = false;
    _error = null;
    return true;
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      beginScreenLoad(
        hasData: _hasData,
        apply: ({required loading, required refreshing, error}) {
          _loading = loading;
          _refreshing = refreshing;
          _error = error;
        },
      );
    });
    try {
      final report = await _api.fetchReport(widget.projectId, _type.id, period: _period, audience: _audience);
      ScreenCache.instance.write(_cacheKey, report);
      if (mounted) {
        setState(() {
          _report = report;
          _hasData = true;
          _loading = false;
          _refreshing = false;
        });
      }
    } catch (e) {
      DashboardLogService.record(projectId: widget.projectId, message: formatLoadError(e));
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  void _setPeriod(PeriodFilter p) {
    _period = p;
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _selectType(ReportType t) {
    if (t == _type) return;
    setState(() => _type = t);
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  void _setAudience(ReportAudience a) {
    if (a == _audience) return;
    setState(() => _audience = a);
    if (_restore()) {
      setState(() {});
    } else {
      _load();
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final enriched = await _api.exportReport(widget.projectId, _type.id, period: _period, audience: _audience);
      await Printing.layoutPdf(onLayout: (_) => buildReportPdf(enriched));
      if (mounted && enriched.snapshotUrl != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF ready · readonly link expires with share token')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openPeriodPicker() => showPeriodPicker(context, current: _period, onSelected: _setPeriod);

  @override
  Widget build(BuildContext context) {
    return AsyncScreenBody(
      loading: _loading,
      refreshing: _refreshing,
      error: _error,
      onRetry: _load,
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final report = _report;
    return ListView(
      padding: pageInsets(context, top: pagePad(context), bottom: pagePad(context)),
      children: [
        PageHeader(
          title: 'Reports',
          subtitle: 'Audience-tailored briefs · ${_period.comparisonLabel()}',
          period: _period,
          onPeriodTap: _openPeriodPicker,
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            _pdfSplitButton(report),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final t in ReportType.values)
              ChoiceChip(label: Text(t.label), selected: _type == t, onSelected: (_) => _selectType(t)),
          ],
        ),
        const SizedBox(height: 12),
        FilterBar(period: _period, onPeriodChanged: _setPeriod),
        const SizedBox(height: 20),
        if (report != null)
          SharedReportView(
            report: report,
            onIssueTap: (issueId) => context.go('/p/${widget.projectId}/issues/$issueId'),
          ),
      ],
    );
  }

  Widget _pdfSplitButton(Report? report) {
    final enabled = report != null && !_exporting;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: enabled ? _exportPdf : null,
          icon: _exporting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_outlined),
          label: Text('PDF: ${_audience.label}'),
          style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(20))),
          ),
        ),
        PopupMenuButton<ReportAudience>(
          tooltip: 'Choose report audience',
          enabled: enabled,
          initialValue: _audience,
          onSelected: _setAudience,
          itemBuilder: (_) => [
            for (final a in ReportAudience.values)
              PopupMenuItem(value: a, child: Text(a == _audience ? '✓ ${a.label}' : a.label)),
          ],
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: FilledButton(
              onPressed: enabled ? () {} : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(36, 40),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(20))),
              ),
              child: const Icon(Icons.arrow_drop_down, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}
