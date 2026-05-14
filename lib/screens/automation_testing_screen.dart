import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/automation_test.dart';
import '../models/test_report.dart';
import '../providers/testing_provider.dart';
import '../utils/constants.dart';
import '../widgets/assertion_alert_card.dart';

/// Phase 4: Automation Testing Screen.
///
/// Sections:
/// 1. Validation Metrics (pass rate, fail rate, totals)
/// 2. Active Tests Panel (running tests with progress)
/// 3. Assertion Monitor (passed/failed/warning list)
/// 4. Test Reports (completed test summaries)
class AutomationTestingScreen extends StatelessWidget {
  const AutomationTestingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TestingProvider>(
      builder: (context, prov, _) {
        return ListView(
          padding: const EdgeInsets.all(AppConstants.screenPadding),
          children: [
            _buildValidationMetrics(prov),
            const SizedBox(height: 12),
            _buildActiveTestsPanel(prov),
            const SizedBox(height: 12),
            _buildAssertionMonitor(prov),
            const SizedBox(height: 12),
            _buildTestReports(prov),
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }

  // ─── 1. Validation Metrics ──────────────────────────────────

  Widget _buildValidationMetrics(TestingProvider prov) {
    return _SectionCard(
      title: 'VALIDATION METRICS',
      icon: Icons.analytics,
      accentColor: AppConstants.neonCyan,
      child: Column(children: [
        Row(children: [
          _MetricTile(label: 'ASSERT RATE', value: '${prov.assertionPassRate.toStringAsFixed(1)}%', color: prov.assertionPassRate >= 90 ? AppConstants.neonGreen : prov.assertionPassRate >= 70 ? AppConstants.neonOrange : AppConstants.neonRed),
          _MetricTile(label: 'TEST RATE', value: '${prov.testPassRate.toStringAsFixed(1)}%', color: prov.testPassRate >= 90 ? AppConstants.neonGreen : AppConstants.neonOrange),
          _MetricTile(label: 'TESTS', value: '${prov.totalTests}', color: AppConstants.neonBlue),
          _MetricTile(label: 'REPORTS', value: '${prov.totalReports}', color: AppConstants.neonMagenta),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _MetricTile(label: 'PASSED', value: '${prov.assertionsPassed}', color: AppConstants.neonGreen),
          _MetricTile(label: 'FAILED', value: '${prov.assertionsFailed}', color: AppConstants.neonRed),
          _MetricTile(label: 'WARNINGS', value: '${prov.assertionsWarning}', color: AppConstants.neonOrange),
          _MetricTile(label: 'AVG DUR', value: _formatDuration(prov.avgTestDurationMs), color: AppConstants.neonCyan),
        ]),
        if (prov.topFailedAssertions.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(color: AppConstants.borderDim, height: 1),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: Text('TOP FAILED ASSERTIONS', style: TextStyle(color: AppConstants.neonRed.withValues(alpha: 0.8), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1))),
          const SizedBox(height: 4),
          ...prov.topFailedAssertions.take(3).map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppConstants.neonRed, size: 12),
              const SizedBox(width: 6),
              Expanded(child: Text(e.key, style: const TextStyle(color: AppConstants.textSecondary, fontSize: 11, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
              Text('×${e.value}', style: const TextStyle(color: AppConstants.neonRed, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
          )),
        ],
      ]),
    );
  }

  // ─── 2. Active Tests Panel ──────────────────────────────────

  Widget _buildActiveTestsPanel(TestingProvider prov) {
    final active = prov.activeTests;
    return _SectionCard(
      title: 'ACTIVE TESTS',
      icon: Icons.play_circle,
      accentColor: AppConstants.neonGreen,
      trailing: active.isNotEmpty ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppConstants.neonGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text('${active.length} RUNNING', style: const TextStyle(color: AppConstants.neonGreen, fontSize: 10, fontWeight: FontWeight.bold))) : null,
      child: active.isEmpty
          ? _buildEmptyState('No active tests', Icons.hourglass_empty)
          : Column(children: active.map((t) => _buildTestCard(t)).toList()),
    );
  }

  Widget _buildTestCard(AutomationTest test) {
    final statusColor = _testStatusColor(test.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppConstants.bgSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: statusColor.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(test.isRunning ? Icons.sync : Icons.check_circle, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(test.testName, style: const TextStyle(color: AppConstants.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)), child: Text(test.status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold))),
        ]),
        if (test.details.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(test.details, style: const TextStyle(color: AppConstants.textDim, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (test.isRunning) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: test.progress / 100, backgroundColor: AppConstants.bgCard, valueColor: AlwaysStoppedAnimation(statusColor), minHeight: 6))),
            const SizedBox(width: 8),
            Text('${test.progress}%', style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
        ],
      ]),
    );
  }

  // ─── 3. Assertion Monitor ───────────────────────────────────

  Widget _buildAssertionMonitor(TestingProvider prov) {
    final asserts = prov.assertions;
    return _SectionCard(
      title: 'ASSERTION MONITOR',
      icon: Icons.verified,
      accentColor: AppConstants.neonYellow,
      trailing: asserts.isNotEmpty ? Text('${asserts.length} entries', style: const TextStyle(color: AppConstants.textDim, fontSize: 10)) : null,
      child: asserts.isEmpty
          ? _buildEmptyState('No assertions received', Icons.rule)
          : Column(children: asserts.take(15).map((a) => AssertionAlertCard(assertion: a)).toList()),
    );
  }

  // ─── 4. Test Reports ────────────────────────────────────────

  Widget _buildTestReports(TestingProvider prov) {
    final reports = prov.reports;
    return _SectionCard(
      title: 'TEST REPORTS',
      icon: Icons.assessment,
      accentColor: AppConstants.neonBlue,
      trailing: reports.isNotEmpty ? Text('${reports.length} reports', style: const TextStyle(color: AppConstants.textDim, fontSize: 10)) : null,
      child: reports.isEmpty
          ? _buildEmptyState('No test reports yet', Icons.description)
          : Column(children: reports.take(10).map((r) => _buildReportCard(r)).toList()),
    );
  }

  Widget _buildReportCard(TestReport report) {
    final statusColor = report.hasFailures ? AppConstants.neonRed : AppConstants.neonGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppConstants.bgSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: statusColor.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(report.hasFailures ? Icons.error : Icons.check_circle, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(report.testName, style: const TextStyle(color: AppConstants.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
          Text(report.formattedTime, style: const TextStyle(color: AppConstants.textDim, fontSize: 10)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _ReportChip('P: ${report.passed}', AppConstants.neonGreen),
          const SizedBox(width: 6),
          _ReportChip('F: ${report.failed}', AppConstants.neonRed),
          const SizedBox(width: 6),
          _ReportChip('W: ${report.warnings}', AppConstants.neonOrange),
          const Spacer(),
          Text(report.formattedDuration, style: const TextStyle(color: AppConstants.neonCyan, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: report.passRate / 100, backgroundColor: AppConstants.neonRed.withValues(alpha: 0.2), valueColor: AlwaysStoppedAnimation(statusColor), minHeight: 4)),
        const SizedBox(height: 2),
        Text('${report.passRate.toStringAsFixed(1)}% pass rate', style: TextStyle(color: statusColor.withValues(alpha: 0.7), fontSize: 10)),
      ]),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: AppConstants.textDim.withValues(alpha: 0.3), size: 32),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: AppConstants.textDim.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(height: 4),
        Text('Waiting for ESP32 test packets...', style: TextStyle(color: AppConstants.textDim.withValues(alpha: 0.3), fontSize: 10)),
      ]),
    );
  }

  Color _testStatusColor(String status) {
    switch (status) {
      case 'RUNNING': return AppConstants.neonCyan;
      case 'PASSED': return AppConstants.neonGreen;
      case 'FAILED': return AppConstants.neonRed;
      case 'WARNING': return AppConstants.neonOrange;
      case 'CANCELLED': return AppConstants.textDim;
      default: return AppConstants.textSecondary;
    }
  }

  String _formatDuration(double ms) {
    if (ms <= 0) return '--';
    if (ms < 1000) return '${ms.toStringAsFixed(0)}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }
}

// ─── Reusable Sub-Widgets ─────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({required this.title, required this.icon, required this.accentColor, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppConstants.bgCard, borderRadius: BorderRadius.circular(AppConstants.cardRadius), border: Border.all(color: accentColor.withValues(alpha: 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(children: [
            Icon(icon, color: accentColor, size: 16),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: accentColor.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
        ),
        const Divider(color: AppConstants.borderDim, height: 1),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ]),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppConstants.textDim, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ]),
      ),
    );
  }
}

class _ReportChip extends StatelessWidget {
  final String text;
  final Color color;
  const _ReportChip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
