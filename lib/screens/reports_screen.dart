import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:garage_manager/screens/billing_screen.dart';
import 'package:garage_manager/screens/report_details_screen.dart';
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
  bool _loading = true;      // first load only: nothing to show yet
  bool _refreshing = false;  // range/pull refresh: keep old data on screen
  int _reqId = 0;            // drops responses from superseded loads
  String? _error;

  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _daily;
  List<dynamic> _newCustomers = [];
  List<dynamic> _services = [];
  List<dynamic> _unpaid = [];
  List<dynamic> _trend = [];
  List<dynamic> _categories = [];
  Map<String, dynamic> _tyres = {};
  Map<String, dynamic> _payModes = {};
  Map<String, dynamic> _bought = {};
  bool _showAllTyres = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_reqId;
    setState(() { _refreshing = true; _error = null; });
    try {
      // All independent; run together so a range change costs one round trip.
      final results = await Future.wait([
        widget.apiService.getAdminSummary(),
        widget.apiService.getDailyReport(_range),
        widget.apiService.getServiceAnalysis(_range),
        widget.apiService.getUnpaidInvoices(),
        widget.apiService.getRevenueTrend(),
        widget.apiService.getRevenueByCategory(_range),
        widget.apiService.getTyreSales(_range),
        widget.apiService.getPaymentModes(_range),
        widget.apiService.getNewCustomers(_range),
        widget.apiService.getTyrePurchases(_range),
      ]);
      if (!mounted || id != _reqId) return;

      setState(() {
        _summary  = (results[0] as Map<String, dynamic>?)?['data'];
        _daily    = (results[1] as Map<String, dynamic>?)?['data'];
        _services = ((results[2] as Map<String, dynamic>?)?['data'] as List?) ?? [];
        _unpaid   = ((results[3] as Map<String, dynamic>?)?['data'] as List?) ?? [];
        _trend    = ((results[4] as Map<String, dynamic>?)?['data'] as List?) ?? [];
        _categories = results[5] as List<dynamic>;
        _tyres      = results[6] as Map<String, dynamic>;
        _payModes   = results[7] as Map<String, dynamic>;
        _newCustomers = results[8] as List<dynamic>;
        _bought       = results[9] as Map<String, dynamic>;
      });
    } catch (e) {
      if (!mounted || id != _reqId) return;
      setState(() => _error = e is ApiException ? e.toString() : 'Failed to load reports.');
    } finally {
      if (mounted && id == _reqId) setState(() { _loading = false; _refreshing = false; });
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
                      RangeChips(selected: _range, onSelect: (r) { setState(() => _range = r); _load(); }),
                      if (_refreshing) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 2, color: _colorPrimary, backgroundColor: _colorInputBg),
                      ],
                      const SizedBox(height: 16),
                      _buildSummarySection(),
                      const SizedBox(height: 16),
                      _buildJobsSection(),
                      const SizedBox(height: 16),
                      _buildRevenueByCategory(),
                      const SizedBox(height: 16),
                      _buildPaymentModes(),
                      const SizedBox(height: 16),
                      _buildTyreSales(),
                      const SizedBox(height: 20),
                      _buildTyresBought(),
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

  // ── Live overview (follows the selected range; Pending Dues is always the total outstanding) ──

  Widget _buildSummarySection() {
    final revenue = _daily?['revenue'] as Map<String, dynamic>? ?? {};
    final jobs    = _daily?['jobs']    as Map<String, dynamic>? ?? {};
    final pendingRevenue = _summary?['revenue']?['pending_revenue'];
    final isToday = _range == 'today';
    final rangeName = _rangeLabel(_range);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Live Overview'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _StatCard(label: isToday ? 'Revenue Today' : 'Revenue · $rangeName', value: _fmt(revenue['total_revenue'], currency: true), color: _colorSuccess,  icon: Icons.currency_rupee_rounded)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: 'Pending Dues',    value: _fmt(pendingRevenue, currency: true),  color: _colorWarning,  icon: Icons.pending_outlined,
              onTap: _openPendingDues)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _StatCard(label: isToday ? 'New Jobs Today' : 'New Jobs · $rangeName', value: _fmt(jobs['total_jobs']), color: _colorPrimary,  icon: Icons.receipt_long_outlined)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: isToday ? 'New Customers' : 'New Customers · $rangeName', value: _fmt(_newCustomers.length), color: _colorInfo,    icon: Icons.person_add_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => NewCustomersScreen(apiService: widget.apiService),
              )))),
        ]),
      ],
    );
  }

  Future<void> _openPendingDues() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PendingDuesScreen(apiService: widget.apiService),
    ));
    _load(); // payments may have been recorded
  }

  // ── Revenue by category ──────────────────────────────────────────────────

  static const _categoryOrder = [
    ('wash',            'Wash',             Icons.water_drop_outlined),
    ('wheel_alignment', 'Wheel Alignment',  Icons.tune),
    ('wheel_balancing', 'Wheel Balancing',  Icons.rotate_right),
    ('tyre',            'Tyre',             Icons.tire_repair),
    ('servicing',       'Servicing',        Icons.build_outlined),
    ('other',           'Other',            Icons.miscellaneous_services_outlined),
  ];

  Widget _buildRevenueByCategory() {
    final byKey = {
      for (final c in _categories) (c as Map)['category']?.toString(): c.cast<String, dynamic>(),
    };
    double n(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
    final totalReceived = _categories.fold<double>(0, (s, c) => s + n((c as Map)['received']));
    final totalBilled   = _categories.fold<double>(0, (s, c) => s + n((c as Map)['billed']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Revenue by Category · ${_rangeLabel(_range)}'),
        const SizedBox(height: 10),
        _InfoCard(children: [
          Row(children: [
            const Expanded(child: SizedBox()),
            const SizedBox(width: 90, child: Text('Received', textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11.5, color: _colorSubtext))),
            const SizedBox(width: 90, child: Text('Billed', textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11.5, color: _colorSubtext))),
          ]),
          const SizedBox(height: 4),
          for (final cat in _categoryOrder)
            if (cat.$1 != 'other' || byKey.containsKey('other'))
              _CategoryRow(
                icon: cat.$3,
                label: cat.$2,
                count: (byKey[cat.$1]?['invoices'] as num?)?.toInt() ?? 0,
                received: n(byKey[cat.$1]?['received']),
                billed: n(byKey[cat.$1]?['billed']),
                share: totalReceived > 0 ? n(byKey[cat.$1]?['received']) / totalReceived : 0,
              ),
          const Divider(height: 20),
          Row(children: [
            const Expanded(child: Text('Total', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _colorHeading))),
            SizedBox(width: 90, child: Text(_rupees(totalReceived), textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _colorSuccess))),
            SizedBox(width: 90, child: Text(_rupees(totalBilled), textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _colorHeading))),
          ]),
          if (totalBilled > totalReceived) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _openPendingDues,
                child: Text('${_rupees(totalBilled - totalReceived)} still to collect ›',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorWarning)),
              ),
            ),
          ],
        ]),
      ],
    );
  }

  // ── Payments by mode ─────────────────────────────────────────────────────

  static const _modeLabels = {
    'cash': ('Cash', Icons.payments_outlined),
    'upi': ('UPI', Icons.qr_code_2),
    'card': ('Card', Icons.credit_card),
    'net_banking': ('Net Banking', Icons.account_balance_outlined),
    'unknown': ('Not recorded', Icons.help_outline),
  };

  Widget _buildPaymentModes() {
    final methods = ((_payModes['methods'] as List?) ?? []).cast<Map>();
    final unpaid  = (_payModes['unpaid'] as Map?) ?? {};
    final unpaidCount = int.tryParse(unpaid['count']?.toString() ?? '') ?? 0;
    final totalCount  = int.tryParse(_payModes['total_count']?.toString() ?? '') ?? 0;
    final totalAmount = double.tryParse(_payModes['total_amount']?.toString() ?? '') ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Payments by Mode · ${_rangeLabel(_range)}'),
        const SizedBox(height: 10),
        _InfoCard(children: [
          if (methods.isEmpty)
            const Text('No paid bills in this period.',
                style: TextStyle(fontSize: 13, color: _colorSubtext)),
          for (final m in methods)
            Builder(builder: (_) {
              final info = _modeLabels[m['method']] ?? (m['method'].toString(), Icons.payments_outlined);
              final amount = double.tryParse(m['amount'].toString()) ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(info.$2, size: 18, color: _colorPrimary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(info.$1,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _colorHeading))),
                    Text('${m['count']} ${m['count'].toString() == '1' ? 'bill' : 'bills'}', style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                    SizedBox(width: 90, child: Text(_rupees(amount), textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _colorHeading))),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(4)),
                    child: LinearProgressIndicator(
                      value: totalAmount > 0 ? amount / totalAmount : 0,
                      backgroundColor: _colorInputBg,
                      color: _colorPrimary,
                      minHeight: 6,
                    ),
                  ),
                ]),
              );
            }),
          if (methods.isNotEmpty) ...[
            const Divider(height: 20),
            Row(children: [
              Expanded(child: Text('Total · $totalCount paid bills',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _colorHeading))),
              Text(_rupees(totalAmount),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _colorSuccess)),
            ]),
          ],
          if (unpaidCount > 0) ...[
            const SizedBox(height: 6),
            Text('$unpaidCount bills unpaid · ${_rupees(double.tryParse(unpaid['amount'].toString()) ?? 0)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorWarning)),
          ],
        ]),
      ],
    );
  }

  // ── Tyres bought from the dealer ─────────────────────────────────────────

  Widget _buildTyresBought() {
    final rows  = ((_bought['rows'] as List?) ?? []).cast<Map>();
    final count = int.tryParse(_bought['total_tyres']?.toString() ?? '') ?? 0;
    final cost  = double.tryParse(_bought['total_cost']?.toString() ?? '') ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Tyres Bought · ${_rangeLabel(_range)}'),
        const SizedBox(height: 10),
        _InfoCard(children: [
          Row(children: [
            Expanded(child: _MiniStat(label: 'Tyres bought', value: '$count')),
            Expanded(child: _MiniStat(label: 'Cost (where entered)', value: _rupees(cost))),
          ]),
          if (rows.isEmpty) ...[
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No tyres bought in this period.',
                  style: TextStyle(fontSize: 13, color: _colorSubtext)),
            ),
          ] else ...[
            const Divider(height: 24),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text('${r['brand'] ?? ''} ${r['size'] ?? ''}'.trim(),
                        style: const TextStyle(fontSize: 13, color: _colorBodyText)),
                  ),
                  Text('×${r['tyres']}  ${_rupees(double.tryParse(r['cost'].toString()) ?? 0)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _colorHeading)),
                ]),
              ),
          ],
        ]),
      ],
    );
  }

  // ── Tyre sales ───────────────────────────────────────────────────────────

  Widget _buildTyreSales() {
    final totals  = (_tyres['totals'] as Map?) ?? {};
    final byBrand = ((_tyres['by_brand'] as List?) ?? []).cast<Map>();
    final byType  = ((_tyres['by_type']  as List?) ?? []).cast<Map>();
    final byTyre  = ((_tyres['by_tyre']  as List?) ?? []).cast<Map>();
    final count   = int.tryParse(totals['tyres']?.toString() ?? '') ?? 0;
    final value   = double.tryParse(totals['value']?.toString() ?? '') ?? 0;
    final maxBrand = byBrand.fold<int>(1, (m, b) => ((b['tyres'] as num?)?.toInt() ?? 0) > m ? (b['tyres'] as num).toInt() : m);
    final shownTyres = _showAllTyres ? byTyre : byTyre.take(5).toList();

    String typeLabel(String t) => t == 'unspecified' ? 'Type not set' : '${t[0].toUpperCase()}${t.substring(1)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Tyre Sales · ${_rangeLabel(_range)}'),
        const SizedBox(height: 10),
        _InfoCard(children: [
          Row(children: [
            Expanded(child: _MiniStat(label: 'Tyres sold', value: '$count')),
            Expanded(child: _MiniStat(label: 'Value (stock price)', value: _rupees(value))),
          ]),
          if (count == 0) ...[
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No tyres sold in this period.',
                  style: TextStyle(fontSize: 13, color: _colorSubtext)),
            ),
          ] else ...[
            if (byType.isNotEmpty) ...[
              const Divider(height: 24),
              const _SubTitle('By type'),
              SizedBox(width: double.infinity, child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in byType)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _colorInputBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${typeLabel(t['type'].toString())} · ${t['tyres']}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _colorHeading)),
                  ),
              ])),
            ],
            const Divider(height: 24),
            const _SubTitle('By brand'),
            for (final b in byBrand)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 80, child: Text(b['brand']?.toString() ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                      child: LinearProgressIndicator(
                        value: ((b['tyres'] as num?)?.toDouble() ?? 0) / maxBrand,
                        backgroundColor: _colorInputBg,
                        color: _colorPrimary,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 36, child: Text('${b['tyres']}', textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading))),
                ]),
              ),
            const Divider(height: 24),
            const _SubTitle('Tyres sold'),
            for (final t in shownTyres)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      [t['brand'], t['model'], t['pattern'], t['size']]
                          .where((e) => e != null && e.toString().trim().isNotEmpty).join(' '),
                      style: const TextStyle(fontSize: 13, color: _colorBodyText),
                    ),
                  ),
                  Text('×${t['tyres']}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _colorHeading)),
                ]),
              ),
            if (byTyre.length > 5)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showAllTyres = !_showAllTyres),
                  child: Text(_showAllTyres ? 'Show fewer' : 'Show all ${byTyre.length}'),
                ),
              ),
          ],
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
            return GestureDetector(
              onTap: m['job_card_id'] == null ? null : () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BillingScreen(apiService: widget.apiService, jobId: m['job_card_id'].toString()),
                ));
                _load();
              },
              child: Container(
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
                const Icon(Icons.chevron_right, color: _colorSubtext),
              ]),
            ),
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
  const _StatCard({required this.label, required this.value, required this.color, required this.icon, this.onTap});
  final String label, value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
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
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _colorSubtext))),
            const SizedBox(width: 6),
            Icon(icon, size: 16, color: color),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.5))),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 20, color: _colorSubtext),
          ]),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: const BorderRadius.all(Radius.circular(14)), child: card),
    );
  }
}

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String _rupees(double v) => _inr.format(v);

class _SubTitle extends StatelessWidget {
  const _SubTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorSubtext)),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _colorHeading)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
        ],
      );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.received,
    required this.billed,
    required this.share,
  });
  final IconData icon;
  final String label;
  final int count;
  final double received, billed, share;

  @override
  Widget build(BuildContext context) {
    final empty = billed == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Row(children: [
          Icon(icon, size: 16, color: empty ? _colorSubtext : _colorPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(count > 0 ? '$label ($count)' : label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: empty ? _colorSubtext : _colorHeading)),
          ),
          SizedBox(width: 90, child: Text(_rupees(received), textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: empty ? _colorSubtext : _colorSuccess))),
          SizedBox(width: 90, child: Text(_rupees(billed), textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: empty ? _colorSubtext : _colorBodyText))),
        ]),
        if (!empty) ...[
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(
              value: share, backgroundColor: _colorInputBg, color: _colorSuccess, minHeight: 5,
            ),
          ),
        ],
      ]),
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
