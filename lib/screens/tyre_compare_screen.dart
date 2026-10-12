import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder  = Color(0xFFE8EAED);
const _colorBg      = Color(0xFFF5F7FA);
const _colorGreen   = Color(0xFF27AE60);
const _colorAmber   = Color(0xFFE67E22);
const _colorRed     = Color(0xFFE53935);

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// "185/65 R15", "185/65R15" and "185 / 65 r15" are the same size.
String sizeKey(String size) => size.toUpperCase().replaceAll(RegExp(r'\s+'), '');

int _qty(Map t) => int.tryParse(t['quantity']?.toString() ?? '') ?? 0;
double? _price(Map t) => double.tryParse(t['price']?.toString() ?? '');

String _tyreName(Map t) => [t['brand'], t['model']]
    .where((e) => e != null && e.toString().trim().isNotEmpty)
    .join(' ');

class _SizeGroup {
  _SizeGroup(this.key, this.label, this.tyres);
  final String key;
  final String label;
  final List<Map<String, dynamic>> tyres;

  int get inStock => tyres.fold(0, (s, t) => s + _qty(t));
  int get brands => tyres.map((t) => t['brand']?.toString().toLowerCase()).toSet().length;
  List<double> get prices => tyres.map(_price).whereType<double>().where((p) => p > 0).toList()..sort();
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — pick a size
// ─────────────────────────────────────────────────────────────────────────────

class TyreCompareScreen extends StatefulWidget {
  const TyreCompareScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<TyreCompareScreen> createState() => _TyreCompareScreenState();
}

class _TyreCompareScreenState extends State<TyreCompareScreen> {
  final _searchCtrl = TextEditingController();
  List<_SizeGroup>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.apiService.getTyres();
      final tyres = ((data as List?) ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();

      final byKey = <String, List<Map<String, dynamic>>>{};
      for (final t in tyres) {
        final size = t['size']?.toString().trim() ?? '';
        if (size.isEmpty) continue;
        byKey.putIfAbsent(sizeKey(size), () => []).add(t);
      }
      final groups = byKey.entries.map((e) {
        // Show the spelling used most often for this size
        final counts = <String, int>{};
        for (final t in e.value) {
          final s = t['size'].toString().trim();
          counts[s] = (counts[s] ?? 0) + 1;
        }
        final label = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
        return _SizeGroup(e.key, label, e.value);
      }).toList()
        // Sizes with more choice first, then by name
        ..sort((a, b) {
          final c = b.tyres.length.compareTo(a.tyres.length);
          return c != 0 ? c : a.label.compareTo(b.label);
        });

      if (mounted) setState(() { _groups = groups; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.toString() : 'Could not load tyre stock.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = sizeKey(_searchCtrl.text.trim());
    final groups = _groups?.where((g) => q.isEmpty || g.key.contains(q)).toList();

    return Scaffold(
      backgroundColor: _colorBg,
      appBar: AppBar(title: const Text('Compare Tyres')),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Search size, e.g. 185/65 R15',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_searchCtrl.clear),
                    ),
            ),
          ),
        ),
        const Divider(height: 1, color: _colorBorder),
        Expanded(
          child: _error != null
              ? _Message(_error!, onRetry: _load)
              : groups == null
                  ? const Center(child: CircularProgressIndicator())
                  : groups.isEmpty
                      ? _Message(_groups!.isEmpty
                          ? 'No tyres in stock yet.\nAdd them in Tyre Stock.'
                          : 'No tyres in this size.')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 8),
                                child: Text('Pick a size to compare brands',
                                    style: TextStyle(fontSize: 13, color: _colorSubtext)),
                              ),
                              for (final g in groups)
                                _SizeTile(
                                  group: g,
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => TyreSizeCompareScreen(size: g.label, tyres: g.tyres),
                                  )),
                                ),
                            ],
                          ),
                        ),
        ),
      ]),
    );
  }
}

class _SizeTile extends StatelessWidget {
  const _SizeTile({required this.group, required this.onTap});
  final _SizeGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final prices = group.prices;
    final range = prices.isEmpty
        ? 'No prices'
        : prices.first == prices.last
            ? _money.format(prices.first)
            : '${_money.format(prices.first)} – ${_money.format(prices.last)}';
    final stock = group.inStock;

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
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group.label,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _colorHeading)),
                const SizedBox(height: 3),
                Text(
                  '${group.brands} brand${group.brands == 1 ? '' : 's'} · $range',
                  style: const TextStyle(fontSize: 12.5, color: _colorSubtext),
                ),
              ]),
            ),
            Text(stock == 0 ? 'No stock' : '$stock in stock',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: stock == 0 ? _colorRed : _colorGreen,
                )),
            const Icon(Icons.chevron_right, color: _colorSubtext),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — every brand in that size, side by side
// ─────────────────────────────────────────────────────────────────────────────

class TyreSizeCompareScreen extends StatelessWidget {
  const TyreSizeCompareScreen({super.key, required this.size, required this.tyres});
  final String size;
  final List<Map<String, dynamic>> tyres;

  @override
  Widget build(BuildContext context) {
    // Cheapest first; tyres without a price go last
    final sorted = [...tyres]..sort((a, b) {
        final pa = _price(a), pb = _price(b);
        if (pa == null && pb == null) return _tyreName(a).compareTo(_tyreName(b));
        if (pa == null) return 1;
        if (pb == null) return -1;
        return pa.compareTo(pb);
      });
    final cheapestInStock = sorted.firstWhere(
      (t) => _qty(t) > 0 && (_price(t) ?? 0) > 0,
      orElse: () => const {},
    );
    final total = tyres.fold<int>(0, (s, t) => s + _qty(t));

    return Scaffold(
      backgroundColor: _colorBg,
      appBar: AppBar(title: Text(size)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _colorBorder),
            ),
            child: Row(children: [
              const Icon(Icons.tire_repair, color: _colorPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${sorted.length} option${sorted.length == 1 ? '' : 's'} in $size',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _colorHeading)),
              ),
              Text('$total in stock',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: total == 0 ? _colorRed : _colorGreen)),
            ]),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Text('Sorted by price, lowest first',
                style: TextStyle(fontSize: 12, color: _colorSubtext)),
          ),
          for (final t in sorted)
            _BrandRow(tyre: t, best: identical(t, cheapestInStock)),
        ],
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow({required this.tyre, required this.best});
  final Map<String, dynamic> tyre;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final qty = _qty(tyre);
    final price = _price(tyre);
    final pattern = tyre['pattern']?.toString().trim() ?? '';
    final type = tyre['vehicle_type']?.toString().trim() ?? '';
    final offer = tyre['offer']?.toString().trim() ?? '';
    final stockColor = qty == 0 ? _colorRed : qty <= 2 ? _colorAmber : _colorGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: qty == 0 ? const Color(0xFFFAFAFB) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: best ? _colorGreen : _colorBorder, width: best ? 1.5 : 1),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(_tyreName(tyre),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: qty == 0 ? _colorSubtext : _colorHeading)),
              ),
              if (best) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _colorGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Best in stock',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _colorGreen)),
                ),
              ],
            ]),
            if (pattern.isNotEmpty || type.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                [if (pattern.isNotEmpty) 'Pattern: $pattern', if (type.isNotEmpty) type].join(' · '),
                style: const TextStyle(fontSize: 12.5, color: _colorSubtext),
              ),
            ],
            if (offer.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(offer, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorAmber)),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(price == null || price == 0 ? 'No price' : _money.format(price),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: price == null || price == 0 ? _colorSubtext : _colorHeading)),
          const SizedBox(height: 4),
          Text(qty == 0 ? 'No stock' : '$qty in stock',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: stockColor)),
        ]),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});
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
