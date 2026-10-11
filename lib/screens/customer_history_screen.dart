import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garage_manager/models/vehicle_types.dart';
import 'package:garage_manager/screens/invoice_print_screen.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder  = Color(0xFFE8EAED);
const _colorBg      = Color(0xFFF5F7FA);
const _colorGood    = Color(0xFF27AE60);
const _colorWarn    = Color(0xFFB9770E);

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _date  = DateFormat('dd MMM yyyy');

/// Stored phones carry the country code (919876543210) — show them readably.
String _fmtPhone(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  if (d.length == 10) return '${d.substring(0, 5)} ${d.substring(5)}';
  return raw;
}

String _relativeDate(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return 'No visits yet';
  final days = DateTime.now().difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 30) return '$days days ago';
  return _date.format(d);
}

String _vehicleDesc(Map v) {
  final makeModel = [v['brand'], v['model']]
      .where((e) => e != null && e.toString().trim().isNotEmpty)
      .join(' ');
  final type = vehicleTypeFor(v['vehicle_type']?.toString())?.label;
  return [v['vehicle_number'], if (makeModel.isNotEmpty) makeModel, if (type != null) type]
      .join(' · ');
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer list
// ─────────────────────────────────────────────────────────────────────────────

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key, required this.apiService, this.embedded = false});
  final ApiService apiService;

  /// Shown inside the main screen's Customers tab — no app bar of its own.
  final bool embedded;

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  static const _pageSize = 30;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  String? _vehicleType;
  String? _service;

  final List<Map<String, dynamic>> _customers = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _requestId = 0; // drops responses from superseded searches

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels > _scrollCtrl.position.maxScrollExtent - 300) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
    setState(() {}); // toggles the clear button
  }

  Future<void> _reload() async {
    _customers.clear();
    _hasMore = true;
    _error = null;
    await _fetch();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _error != null) return;
    await _fetch();
  }

  Future<void> _fetch() async {
    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final rows = await widget.apiService.searchCustomers(
        query: _searchCtrl.text.trim(),
        service: _service,
        vehicleType: _vehicleType,
        limit: _pageSize,
        offset: _customers.length,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _customers.addAll(rows.cast<Map>().map((m) => m.cast<String, dynamic>()));
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = e is ApiException ? e.toString() : 'Could not load customers.');
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  bool get _filtered =>
      _searchCtrl.text.trim().isNotEmpty || _vehicleType != null || _service != null;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() { _vehicleType = null; _service = null; });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colorBg,
      appBar: widget.embedded ? null : AppBar(title: const Text('Customers')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search by name or phone number',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () { _searchCtrl.clear(); _onSearchChanged(''); },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                _FilterRow(
                  label: 'Vehicle',
                  options: [for (final t in kVehicleTypes) (t.value, t.label)],
                  selected: _vehicleType,
                  onSelect: (v) { setState(() => _vehicleType = v); _reload(); },
                ),
                const SizedBox(height: 6),
                _FilterRow(
                  label: 'Service',
                  options: kServiceTypes,
                  selected: _service,
                  onSelect: (v) { setState(() => _service = v); _reload(); },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _colorBorder),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_customers.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customers.isEmpty && _error != null) {
      return _Message(
        icon: Icons.error_outline,
        text: _error!,
        action: TextButton(onPressed: _reload, child: const Text('Retry')),
      );
    }
    if (_customers.isEmpty) {
      return _Message(
        icon: Icons.person_search_outlined,
        text: _filtered ? 'No customers match these filters.' : 'No customers yet.',
        action: _filtered
            ? TextButton(onPressed: _clearFilters, child: const Text('Clear filters'))
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _customers.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _customers.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final c = _customers[i];
          return _CustomerTile(
            customer: c,
            highlightType: _vehicleType,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(apiService: widget.apiService, customer: c),
            )),
          );
        },
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
  });
  final String label;
  final List<(String, String)> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, bool sel, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(text),
            selected: sel,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(fontSize: 12.5, color: sel ? Colors.white : _colorHeading),
            selectedColor: _colorPrimary,
            backgroundColor: const Color(0xFFF0F2F5),
            side: BorderSide.none,
          ),
        );

    return Row(children: [
      SizedBox(
        width: 58,
        child: Text(label, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('All', selected == null, () => onSelect(null)),
            for (final o in options)
              chip(o.$2, selected == o.$1, () => onSelect(selected == o.$1 ? null : o.$1)),
          ]),
        ),
      ),
    ]);
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.onTap, this.highlightType});
  final Map<String, dynamic> customer;
  final VoidCallback onTap;

  /// When filtering by vehicle type, show a vehicle of that type first.
  final String? highlightType;

  @override
  Widget build(BuildContext context) {
    final name = customer['name']?.toString() ?? 'Unknown';
    final vehicles = [...(customer['vehicles'] as List? ?? []).cast<Map>()];
    if (highlightType != null) {
      final i = vehicles.indexWhere((v) => v['vehicle_type']?.toString() == highlightType);
      if (i > 0) vehicles.insert(0, vehicles.removeAt(i));
    }
    final visits = customer['visit_count'] ?? 0;
    final type = vehicles.isEmpty ? null : vehicleTypeFor(vehicles.first['vehicle_type']?.toString());

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
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFE9EDF2),
              child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: _colorPrimary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
                const SizedBox(height: 2),
                Text(_fmtPhone(customer['phone']?.toString() ?? ''),
                    style: const TextStyle(fontSize: 13, color: _colorSubtext)),
                if (vehicles.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(type?.icon ?? Icons.directions_car_outlined, size: 14, color: _colorSubtext),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _vehicleDesc(vehicles.first) +
                            (vehicles.length > 1 ? '  +${vehicles.length - 1} more' : ''),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _colorHeading),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_relativeDate(customer['last_visit']),
                  style: const TextStyle(fontSize: 12, color: _colorHeading)),
              const SizedBox(height: 2),
              Text('$visits visit${visits == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11.5, color: _colorSubtext)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: _colorSubtext),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: _colorSubtext)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Customer details
// ─────────────────────────────────────────────────────────────────────────────

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.apiService, required this.customer});
  final ApiService apiService;
  final Map<String, dynamic> customer;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<List<dynamic>> _jobs;

  Map<String, dynamic> get c => widget.customer;

  @override
  void initState() {
    super.initState();
    _jobs = widget.apiService.getCustomerJobs(c['id'].toString());
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not open that app.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = c['phone']?.toString() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final vehicles = (c['vehicles'] as List? ?? []).cast<Map>();
    final spent = double.tryParse(c['total_spent']?.toString() ?? '') ?? 0;

    return Scaffold(
      backgroundColor: _colorBg,
      appBar: AppBar(title: Text(c['name']?.toString() ?? 'Customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(children: [
            Text(c['name']?.toString() ?? '',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _colorHeading)),
            const SizedBox(height: 4),
            Text(_fmtPhone(phone), style: const TextStyle(fontSize: 15, color: _colorSubtext)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: digits.isEmpty ? null : () => _launch(Uri(scheme: 'tel', path: '+$digits')),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: digits.isEmpty ? null : () => _launch(Uri.parse('https://wa.me/$digits')),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('WhatsApp'),
                ),
              ),
            ]),
            const Divider(height: 28),
            Row(children: [
              _Stat('Visits', '${c['visit_count'] ?? 0}'),
              _Stat('Total billed', _money.format(spent)),
              _Stat('Last visit', _relativeDate(c['last_visit'])),
            ]),
          ]),
          const SizedBox(height: 12),

          _Card(children: [
            const _SectionLabel('Vehicles'),
            if (vehicles.isEmpty)
              const Text('No vehicles', style: TextStyle(color: _colorSubtext)),
            for (final v in vehicles) _VehicleRow(vehicle: v),
          ]),
          const SizedBox(height: 12),

          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: _SectionLabel('Visit history'),
          ),
          FutureBuilder<List<dynamic>>(
            future: _jobs,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Text(snap.error.toString(), style: const TextStyle(color: Colors.red));
              }
              final jobs = (snap.data ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
              if (jobs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No visits yet.', style: TextStyle(color: _colorSubtext)),
                );
              }
              return Column(children: [
                for (final j in jobs)
                  _VisitCard(
                    job: j,
                    onViewInvoice: j['invoice_id'] == null
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => InvoicePrintScreen(
                                apiService: widget.apiService,
                                invoiceId: j['invoice_id'].toString(),
                              ),
                            )),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _colorBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _colorHeading)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
        ]),
      );
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.vehicle});
  final Map vehicle;

  @override
  Widget build(BuildContext context) {
    final type = vehicleTypeFor(vehicle['vehicle_type']?.toString());
    final makeModel = [vehicle['brand'], vehicle['model']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' ');
    final sub = [if (makeModel.isNotEmpty) makeModel, if (type != null) type.label].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(type?.icon ?? Icons.directions_car_outlined, size: 22, color: _colorPrimary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(vehicle['vehicle_number']?.toString() ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _colorHeading)),
            Text(sub.isEmpty ? 'Type not recorded' : sub,
                style: const TextStyle(fontSize: 12, color: _colorSubtext)),
          ]),
        ),
      ]),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.job, this.onViewInvoice});
  final Map<String, dynamic> job;
  final VoidCallback? onViewInvoice;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(job['created_at']?.toString() ?? '')?.toLocal();
    final status = job['status']?.toString() ?? '';
    final amount = double.tryParse(job['total_amount']?.toString() ?? '');
    final paid = job['payment_status'] == 'paid';
    final statusColor = switch (status) {
      'completed'   => _colorGood,
      'in_progress' => const Color(0xFF2F80ED),
      'cancelled'   => _colorSubtext,
      _             => _colorWarn,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(serviceLabel(job['service_type']?.toString()),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _colorHeading)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status.replaceAll('_', ' '),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${date == null ? '' : _date.format(date)} · ${job['vehicle_number'] ?? ''}',
          style: const TextStyle(fontSize: 12.5, color: _colorSubtext),
        ),
        if ((job['notes']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(job['notes'].toString(), style: const TextStyle(fontSize: 12.5, color: _colorHeading)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Text(
            amount == null ? 'Not billed' : _money.format(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: amount == null ? _colorSubtext : _colorHeading,
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: 8),
            Text(paid ? 'Paid' : 'Payment pending',
                style: TextStyle(fontSize: 12, color: paid ? _colorGood : _colorWarn)),
          ],
          const Spacer(),
          if (onViewInvoice != null)
            TextButton.icon(
              onPressed: onViewInvoice,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Invoice'),
            ),
        ]),
      ]),
    );
  }
}
