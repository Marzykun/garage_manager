import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garage_manager/models/vehicle_types.dart';
import 'package:garage_manager/screens/billing_screen.dart';
import 'package:garage_manager/screens/customer_history_screen.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder  = Color(0xFFE8EAED);
const _colorBg      = Color(0xFFF5F7FA);
const _colorWarning = Color(0xFFE67E22);
const _colorDanger  = Color(0xFFE53935);

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _date  = DateFormat('dd MMM yyyy');

double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

String _fmtPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  if (d.length == 10) return '${d.substring(0, 5)} ${d.substring(5)}';
  return raw;
}

Future<void> _call(BuildContext context, String phone) async {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return;
  try {
    await launchUrl(Uri(scheme: 'tel', path: d.length == 10 ? '+91$d' : '+$d'),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open the dialer.')));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending dues — every unpaid invoice, oldest first
// ─────────────────────────────────────────────────────────────────────────────

class PendingDuesScreen extends StatefulWidget {
  const PendingDuesScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<PendingDuesScreen> createState() => _PendingDuesScreenState();
}

class _PendingDuesScreenState extends State<PendingDuesScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.apiService.getUnpaidInvoices();
      final list = ((r as Map<String, dynamic>?)?['data'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _rows = list.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.toString() : 'Could not load pending dues.');
    }
  }

  Future<void> _open(Map<String, dynamic> inv) async {
    final jobId = inv['job_card_id']?.toString();
    if (jobId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BillingScreen(apiService: widget.apiService, jobId: jobId),
    ));
    _load(); // it may have been marked paid
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final total = rows?.fold<double>(0, (s, r) => s + _num(r['total_amount'])) ?? 0;

    return Scaffold(
      backgroundColor: _colorBg,
      appBar: AppBar(title: const Text('Pending Payments')),
      body: _error != null
          ? _Message(text: _error!, onRetry: _load)
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _TotalBanner(
                        label: rows.isEmpty
                            ? 'Nothing pending'
                            : '${rows.length} unpaid bill${rows.length == 1 ? '' : 's'}',
                        value: _money.format(total),
                        color: rows.isEmpty ? const Color(0xFF27AE60) : _colorWarning,
                      ),
                      const SizedBox(height: 4),
                      if (rows.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
                          child: Text('Tap a bill to open it and record the payment.',
                              style: TextStyle(fontSize: 12, color: _colorSubtext)),
                        ),
                      for (final inv in rows) _PendingTile(
                        inv: inv,
                        onTap: () => _open(inv),
                        onCall: () => _call(context, inv['customer_phone']?.toString() ?? ''),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.inv, required this.onTap, required this.onCall});
  final Map<String, dynamic> inv;
  final VoidCallback onTap, onCall;

  @override
  Widget build(BuildContext context) {
    final days = int.tryParse(inv['days_pending']?.toString() ?? '') ?? 0;
    final no = inv['invoice_no'];
    final created = DateTime.tryParse(inv['created_at']?.toString() ?? '')?.toLocal();
    final age = days <= 0 ? 'Today' : days == 1 ? '1 day' : '$days days';
    final ageColor = days >= 7 ? _colorDanger : days >= 1 ? _colorWarning : _colorSubtext;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _colorBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv['customer_name']?.toString() ?? '—',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
                const SizedBox(height: 2),
                Text(
                  [
                    inv['vehicle_number'] ?? '',
                    serviceLabel(inv['service_type']?.toString()),
                    if (no != null) 'INV-${no.toString().padLeft(4, '0')}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12.5, color: _colorSubtext),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 13, color: ageColor),
                  const SizedBox(width: 4),
                  Text(
                    days <= 0 ? 'Billed today' : 'Pending $age${created == null ? '' : ' · since ${_date.format(created)}'}',
                    style: TextStyle(fontSize: 12, color: ageColor, fontWeight: FontWeight.w500),
                  ),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_money.format(_num(inv['total_amount'])),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _colorWarning)),
              IconButton(
                tooltip: 'Call ${_fmtPhone(inv['customer_phone']?.toString() ?? '')}',
                visualDensity: VisualDensity.compact,
                onPressed: onCall,
                icon: const Icon(Icons.call_outlined, size: 20, color: _colorPrimary),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New customers in a period
// ─────────────────────────────────────────────────────────────────────────────

class NewCustomersScreen extends StatefulWidget {
  const NewCustomersScreen({super.key, required this.apiService, this.initialRange = 'today'});
  final ApiService apiService;
  final String initialRange;

  @override
  State<NewCustomersScreen> createState() => _NewCustomersScreenState();
}

class _NewCustomersScreenState extends State<NewCustomersScreen> {
  late String _range = widget.initialRange;
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _rows = null; _error = null; });
    try {
      final list = await widget.apiService.getNewCustomers(_range);
      if (mounted) setState(() => _rows = list.cast<Map>().map((m) => m.cast<String, dynamic>()).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.toString() : 'Could not load new customers.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: _colorBg,
      appBar: AppBar(title: const Text('New Customers')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: RangeChips(selected: _range, onSelect: (r) { setState(() => _range = r); _load(); }),
        ),
        Expanded(
          child: _error != null
              ? _Message(text: _error!, onRetry: _load)
              : rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? const _Message(text: 'No new customers in this period.')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text('${rows.length} new customer${rows.length == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorSubtext)),
                            ),
                            for (final c in rows) _NewCustomerTile(
                              c: c,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CustomerDetailScreen(apiService: widget.apiService, customer: c),
                              )),
                            ),
                          ],
                        ),
        ),
      ]),
    );
  }
}

class _NewCustomerTile extends StatelessWidget {
  const _NewCustomerTile({required this.c, required this.onTap});
  final Map<String, dynamic> c;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vehicles = (c['vehicles'] as List? ?? []).cast<Map>();
    final v = vehicles.isEmpty ? null : vehicles.first;
    final type = vehicleTypeFor(v?['vehicle_type']?.toString());
    final added = DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();
    final first = c['first_service']?.toString();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _colorBorder),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE9EDF2),
          child: Icon(type?.icon ?? Icons.person_outline, size: 20, color: _colorPrimary),
        ),
        title: Text(c['name']?.toString() ?? '—',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
        subtitle: Text(
          [
            _fmtPhone(c['phone']?.toString() ?? ''),
            if (v != null) v['vehicle_number'],
            if (first != null) serviceLabel(first),
          ].join(' · '),
          style: const TextStyle(fontSize: 12.5, color: _colorSubtext),
        ),
        trailing: Text(added == null ? '' : _date.format(added),
            style: const TextStyle(fontSize: 12, color: _colorSubtext)),
      ),
    );
  }
}

// ─── Shared ──────────────────────────────────────────────────────────────────

/// Today / 7 Days / 30 Days selector shared by the report screens.
class RangeChips extends StatelessWidget {
  const RangeChips({super.key, required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (final r in const [('today', 'Today'), ('week', '7 Days'), ('month', '30 Days')])
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(r.$2),
            selected: selected == r.$1,
            onSelected: (_) => onSelect(r.$1),
            showCheckmark: false,
            selectedColor: _colorPrimary,
            backgroundColor: Colors.white,
            labelStyle: TextStyle(
                fontSize: 13, color: selected == r.$1 ? Colors.white : _colorHeading),
            side: BorderSide(color: selected == r.$1 ? _colorPrimary : const Color(0xFFE0E4EA)),
          ),
        ),
    ]);
  }
}

class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _colorBorder),
        ),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: _colorHeading))),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: _colorSubtext)),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}
