import 'package:flutter/material.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary    = Color(0xFF2D3A4A);
const _colorHeading    = Color(0xFF1A2332);
const _colorSubtext    = Color(0xFF7A869A);
const _colorBodyText   = Color(0xFF4A5568);
const _colorBorder     = Color(0xFFE8EAED);
const _colorInputBg    = Color(0xFFF0F2F5);
const _colorSuccess    = Color(0xFF27AE60);
const _colorWarning    = Color(0xFFE67E22);
const _colorInfo       = Color(0xFF2980B9);
const _colorErrorText  = Color(0xFFE53935);

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _range = 'today';
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _daily;
  List<dynamic> _services = [];
  List<dynamic> _unpaid = [];
  List<dynamic> _trend = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        widget.apiService.getAdminSummary(),
        widget.apiService.getDailyReport(_range),
        widget.apiService.getServiceAnalysis(_range),
        widget.apiService.getUnpaidInvoices(),
        widget.apiService.getRevenueTrend(),
      ]);

      _summary  = (results[0] as Map<String, dynamic>?)?['data'];
      _daily    = (results[1] as Map<String, dynamic>?)?['data'];
      _services = ((results[2] as Map<String, dynamic>?)?['data'] as List?) ?? [];
      _unpaid   = ((results[3] as Map<String, dynamic>?)?['data'] as List?) ?? [];
      _trend    = ((results[4] as Map<String, dynamic>?)?['data'] as List?) ?? [];
    } catch (e) {
      _error = e is ApiException ? e.toString() : 'Failed to load reports.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(dynamic v, {bool currency = false}) {
    if (v == null) return currency ? '₹0' : '0';
    final n = double.tryParse(v.toString()) ?? 0;
    if (currency) {
      return '₹${n.toStringAsFixed(n == n.truncate() ? 0 : 2)}';
    }
    return n.truncate().toString();
  }

  @override
  Widget build(BuildContext context) {
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: _colorErrorText), textAlign: TextAlign.center),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _colorPrimary,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _RangePicker(selected: _range, onSelect: (r) { setState(() => _range = r); _load(); }),
                      const SizedBox(height: 16),
                      _buildSummarySection(),
                      const SizedBox(height: 16),
                      _buildJobsSection(),
                      const SizedBox(height: 16),
                      _buildServiceBreakdown(),
                      const SizedBox(height: 16),
                      _buildRevenueTrend(),
                      const SizedBox(height: 16),
                      _buildUnpaidInvoices(),
                      const SizedBox(height: 40),
                    ],
                  ),
                );
  }

  // ── Live summary (always today) ──────────────────────────────────────────

  Widget _buildSummarySection() {
    final jobs     = _summary?['jobs']     as Map<String, dynamic>? ?? {};
    final revenue  = _summary?['revenue']  as Map<String, dynamic>? ?? {};
    final customers = _summary?['customers'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Live Overview'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatCard(label: 'Revenue Today',   value: _fmt(revenue['revenue_today'], currency: true),   color: _colorSuccess,  icon: Icons.currency_rupee_rounded)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: 'Pending Dues',    value: _fmt(revenue['pending_revenue'], currency: true),  color: _colorWarning,  icon: Icons.pending_outlined)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _StatCard(label: 'New Jobs Today',  value: _fmt(jobs['new_jobs_today']),      color: _colorPrimary,  icon: Icons.receipt_long_outlined)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: 'New Customers',   value: _fmt(customers['new_customers_today']), color: _colorInfo,    icon: Icons.person_add_outlined)),
        ]),
      ],
    );
  }

  // ── Job counts for selected range ────────────────────────────────────────

  Widget _buildJobsSection() {
    final jobs    = _daily?['jobs']    as Map<String, dynamic>? ?? {};
    final revenue = _daily?['revenue'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Jobs · ${_rangeLabel(_range)}'),
        const SizedBox(height: 10),
        _InfoCard(children: [
          _InfoRow(label: 'Total Jobs',   value: _fmt(jobs['total_jobs'])),
          _InfoRow(label: 'Completed',    value: _fmt(jobs['completed_jobs']),   valueColor: _colorSuccess),
          _InfoRow(label: 'In Progress',  value: _fmt(jobs['in_progress_jobs']), valueColor: _colorInfo),
          _InfoRow(label: 'Pending',      value: _fmt(jobs['pending_jobs']),     valueColor: _colorWarning),
          const Divider(height: 20),
          _InfoRow(label: 'Gross Revenue',  value: _fmt(revenue['gross_revenue'],  currency: true)),
          _InfoRow(label: 'Collected',      value: _fmt(revenue['total_revenue'],  currency: true), valueColor: _colorSuccess),
          _InfoRow(label: 'Unpaid',         value: _fmt(revenue['unpaid_invoices']), valueColor: _colorWarning),
        ]),
      ],
    );
  }

  // ── Service breakdown ─────────────────────────────────────────────────────

  Widget _buildServiceBreakdown() {
    if (_services.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Service Breakdown · ${_rangeLabel(_range)}'),
        const SizedBox(height: 10),
        _InfoCard(children: _services.map((s) {
          final m    = s as Map<String, dynamic>;
          final type = (m['service_type']?.toString() ?? '').replaceAll('_', ' ').split(' ')
              .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
          final total     = int.tryParse(m['total_jobs']?.toString() ?? '0') ?? 0;
          final completed = int.tryParse(m['completed']?.toString() ?? '0') ?? 0;
          final pct       = total > 0 ? (m['percentage']?.toString() ?? '0') : '0';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading))),
                  Text('$completed/$total done', style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                  const SizedBox(width: 8),
                  Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorPrimary)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  child: LinearProgressIndicator(
                    value: total > 0 ? (double.tryParse(pct) ?? 0) / 100 : 0,
                    backgroundColor: _colorInputBg,
                    color: _colorPrimary,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }).toList()),
      ],
    );
  }

  // ── Revenue trend (last 7 days) ───────────────────────────────────────────

  Widget _buildRevenueTrend() {
    if (_trend.isEmpty) return const SizedBox.shrink();

    final max = _trend.fold<double>(1, (prev, t) {
      final v = double.tryParse((t as Map)['revenue']?.toString() ?? '0') ?? 0;
      return v > prev ? v : prev;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Revenue — Last 7 Days'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(14)),
            border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _trend.map((t) {
              final m   = t as Map<String, dynamic>;
              final rev = double.tryParse(m['revenue']?.toString() ?? '0') ?? 0;
              final frac = rev / max;
              final dateStr = m['date']?.toString() ?? '';
              final day = dateStr.length >= 10
                  ? dateStr.substring(8, 10)
                  : dateStr;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('₹${rev == 0 ? '0' : rev.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 9, color: _colorSubtext),
                          overflow: TextOverflow.visible, maxLines: 1),
                      const SizedBox(height: 4),
                      Container(
                        height: 80 * frac.clamp(0.04, 1.0),
                        decoration: BoxDecoration(
                          color: frac > 0.01 ? _colorPrimary : _colorInputBg,
                          borderRadius: const BorderRadius.all(Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(day, style: const TextStyle(fontSize: 10, color: _colorSubtext)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Unpaid invoices ───────────────────────────────────────────────────────

  Widget _buildUnpaidInvoices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Unpaid Invoices (${_unpaid.length})'),
        const SizedBox(height: 10),
        if (_unpaid.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(14)),
              border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_outline_rounded, size: 18, color: _colorSuccess),
              SizedBox(width: 8),
              Text('All invoices are paid.', style: TextStyle(fontSize: 14, color: _colorSuccess, fontWeight: FontWeight.w500)),
            ]),
          )
        else
          ..._unpaid.map((inv) {
            final m = inv as Map<String, dynamic>;
            final type = (m['service_type']?.toString() ?? '').replaceAll('_', ' ');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
              ),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['vehicle_number']?.toString() ?? '—',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _colorHeading)),
                    Text('${m['customer_name'] ?? ''} · $type',
                        style: const TextStyle(fontSize: 12, color: _colorBodyText)),
                  ],
                )),
                Text(_fmt(m['total_amount'], currency: true),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _colorWarning)),
              ]),
            );
          }),
      ],
    );
  }
}

String _rangeLabel(String range) {
  switch (range) {
    case 'today': return 'Today';
    case 'week':  return 'Last 7 Days';
    case 'month': return 'Last 30 Days';
    default:      return range;
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final r in [('today', 'Today'), ('week', '7 Days'), ('month', '30 Days')])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(r.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected == r.$1 ? _colorPrimary : Colors.white,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.fromBorderSide(BorderSide(
                    color: selected == r.$1 ? _colorPrimary : const Color(0xFFE0E4EA),
                  )),
                ),
                child: Text(r.$2,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500,
                    color: selected == r.$1 ? Colors.white : _colorBodyText,
                  )),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorSubtext, letterSpacing: 0.2));
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color, required this.icon});
  final String label, value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
            Icon(icon, size: 16, color: color),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.5)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor = _colorHeading});
  final String label, value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: _colorBodyText))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor)),
      ]),
    );
  }
}
