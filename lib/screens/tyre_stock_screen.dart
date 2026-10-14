import 'package:flutter/material.dart';
import 'package:garage_manager/screens/tyre_compare_screen.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary  = Color(0xFF2D3A4A);
const _colorHeading  = Color(0xFF1A2332);
const _colorSubtext  = Color(0xFF7A869A);
const _colorBorder   = Color(0xFFE8EAED);
const _colorGreen    = Color(0xFF2E7D32);
const _colorRed      = Color(0xFFE53935);
const _colorAmber    = Color(0xFFF59E0B);

class TyreStockScreen extends StatefulWidget {
  const TyreStockScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<TyreStockScreen> createState() => _TyreStockScreenState();
}

class _TyreStockScreenState extends State<TyreStockScreen> {
  List<dynamic> _tyres = [];
  List<dynamic> _dupes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loadDuplicates();
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.apiService.getTyres();
      if (mounted) setState(() => _tyres = data is List ? data : []);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.toString() : 'Failed to load tyre stock.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Owner-only endpoint: any failure (e.g. 403 for staff) just hides the action.
  Future<void> _loadDuplicates() async {
    try {
      final d = await widget.apiService.getTyreDuplicates();
      if (mounted) setState(() => _dupes = d);
    } catch (_) {
      if (mounted) setState(() => _dupes = []);
    }
  }

  Future<void> _openMerge() async {
    String line(Map g) {
      final name = [g['brand'], g['model'], g['size'], g['vehicle_type']]
          .where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
      final qtys = (g['rows'] as List).map((r) => r['quantity'] ?? 0).join(' + ');
      return '$name: $qtys → ${g['merged_quantity']}';
    }
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Merge duplicate tyres',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _colorHeading)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final g in _dupes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(line(g as Map), style: const TextStyle(fontSize: 14, color: _colorHeading)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Merge ${_dupes.length} groups. This cannot be undone.'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final res = await widget.apiService.mergeTyreDuplicates();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Merged ${res['merged_groups']} groups (${res['removed_rows']} duplicate rows removed)')));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.toString() : 'Failed to merge tyres.')),
        );
      }
    }
  }

  Future<void> _deleteTyre(Map<String, dynamic> tyre) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Tyre?'),
        content: Text('Remove ${tyre['brand']} ${tyre['size']} from stock?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: _colorRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.apiService.deleteTyre(tyre['id'].toString());
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.toString() : 'Failed to remove tyre.')),
        );
      }
    }
  }

  void _openForm({Map<String, dynamic>? tyre}) async {
    final saved = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TyreForm(apiService: widget.apiService, existing: tyre),
    );
    if (saved == null) return;
    _load();
    if (saved is String && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Tyre Stock'),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
        // App theme sets a dark title/icon style; override it on this dark bar
        titleTextStyle: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => TyreCompareScreen(apiService: widget.apiService),
            )),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.compare_arrows_rounded, size: 20),
            label: const Text('Compare'),
          ),
          if (_dupes.isNotEmpty)
            IconButton(
              tooltip: 'Merge duplicates',
              icon: Badge(
                label: Text('${_dupes.length}'),
                child: const Icon(Icons.merge_type),
              ),
              onPressed: _openMerge,
            ),
          IconButton(
            tooltip: 'Purchase history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _PurchaseHistoryScreen(apiService: widget.apiService),
            )),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Tyre'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: _colorRed)))
              : _tyres.isEmpty
                  ? const Center(
                      child: Text('No tyres in stock.\nTap + to add some.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _colorSubtext, fontSize: 15)),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _tyres.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _TyreCard(
                          tyre: _tyres[i] as Map<String, dynamic>,
                          onEdit: () => _openForm(tyre: _tyres[i] as Map<String, dynamic>),
                          onDelete: () => _deleteTyre(_tyres[i] as Map<String, dynamic>),
                        ),
                      ),
                    ),
    );
  }
}

// ── Tyre Card ─────────────────────────────────────────────────────────────────

class _TyreCard extends StatelessWidget {
  const _TyreCard({required this.tyre, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> tyre;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final brand = tyre['brand']?.toString() ?? '';
    final model = tyre['model']?.toString() ?? '';
    final pattern = tyre['pattern']?.toString() ?? '';
    final size  = tyre['size']?.toString()  ?? '';
    final qty   = int.tryParse(tyre['quantity']?.toString() ?? '0') ?? 0;
    final price = tyre['price'];
    final offer = tyre['offer']?.toString() ?? '';
    final vType = tyre['vehicle_type']?.toString() ?? '';

    final stockColor = qty == 0 ? _colorRed : qty <= 2 ? _colorAmber : _colorGreen;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _colorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left — icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tire_repair, size: 26, color: _colorPrimary),
          ),
          const SizedBox(width: 12),

          // Middle — details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.isNotEmpty ? '$brand $model' : brand,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading),
                ),
                const SizedBox(height: 3),
                Text(pattern.isNotEmpty ? '$size · Pattern: $pattern' : size,
                    style: const TextStyle(fontSize: 13, color: _colorSubtext)),
                if (vType.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(vType, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Chip(
                      label: 'Qty: $qty',
                      color: stockColor,
                    ),
                    if (price != null) ...[
                      const SizedBox(width: 8),
                      _Chip(
                        label: '₹${_formatPrice(price)}',
                        color: _colorPrimary,
                      ),
                    ],
                    if (offer.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _Chip(label: offer, color: _colorAmber),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Right — actions
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: _colorSubtext),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: _colorRed),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(dynamic price) {
    final d = double.tryParse(price.toString()) ?? 0;
    return d == d.truncateToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Add / Edit Form ───────────────────────────────────────────────────────────

class _TyreForm extends StatefulWidget {
  const _TyreForm({required this.apiService, this.existing});
  final ApiService apiService;
  final Map<String, dynamic>? existing;

  @override
  State<_TyreForm> createState() => _TyreFormState();
}

class _TyreFormState extends State<_TyreForm> {
  final _brandCtrl  = TextEditingController();
  final _modelCtrl  = TextEditingController();
  final _patternCtrl = TextEditingController();
  final _sizeCtrl   = TextEditingController();
  final _vTypeCtrl  = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _priceCtrl  = TextEditingController();
  final _offerCtrl  = TextEditingController();
  final _costCtrl   = TextEditingController();
  final _dealerCtrl = TextEditingController();
  bool  _saving     = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.existing!;
      _brandCtrl.text  = t['brand']?.toString()         ?? '';
      _modelCtrl.text  = t['model']?.toString()         ?? '';
      _patternCtrl.text = t['pattern']?.toString()      ?? '';
      _sizeCtrl.text   = t['size']?.toString()          ?? '';
      _vTypeCtrl.text  = t['vehicle_type']?.toString()  ?? '';
      _qtyCtrl.text    = (t['quantity'] ?? 0).toString();
      _priceCtrl.text  = t['price'] != null ? double.tryParse(t['price'].toString())?.toStringAsFixed(0) ?? '' : '';
      _offerCtrl.text  = t['offer']?.toString()         ?? '';
    }
  }

  @override
  void dispose() {
    _brandCtrl.dispose(); _modelCtrl.dispose(); _sizeCtrl.dispose(); _patternCtrl.dispose();
    _vTypeCtrl.dispose(); _qtyCtrl.dispose(); _priceCtrl.dispose();
    _offerCtrl.dispose(); _costCtrl.dispose(); _dealerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final brand = _brandCtrl.text.trim();
    final size  = _sizeCtrl.text.trim();
    if (brand.isEmpty || size.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brand and Size are required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final qty   = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
      final price = double.tryParse(_priceCtrl.text.trim());

      Object result = true;
      if (_isEdit) {
        final res = await widget.apiService.updateTyre(
          widget.existing!['id'].toString(),
          brand:       brand,
          size:        size,
          model:       _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
          // sent as '' when cleared, so an edit can remove the pattern
          pattern:     _patternCtrl.text.trim(),
          vehicleType: _vTypeCtrl.text.trim().isEmpty ? null : _vTypeCtrl.text.trim(),
          quantity:    qty,
          price:       price,
          offer:       _offerCtrl.text.trim().isEmpty ? null : _offerCtrl.text.trim(),
        );
        if (res is Map && res['merged'] == true) {
          final t = (res['data'] as Map?) ?? {};
          final name = [t['brand'], t['model'], t['size']]
              .where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
          result = 'Merged into existing $name (now ${t['quantity']})';
        }
      } else {
        final res = await widget.apiService.addTyre(
          unitCost:    double.tryParse(_costCtrl.text.trim()),
          dealer:      _dealerCtrl.text.trim(),
          brand:       brand,
          size:        size,
          model:       _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
          pattern:     _patternCtrl.text.trim().isEmpty ? null : _patternCtrl.text.trim(),
          vehicleType: _vTypeCtrl.text.trim().isEmpty ? null : _vTypeCtrl.text.trim(),
          quantity:    qty,
          price:       price,
          offer:       _offerCtrl.text.trim().isEmpty ? null : _offerCtrl.text.trim(),
        );
        if (res is Map && res['merged'] == true) {
          final t = (res['data'] as Map?) ?? {};
          final name = [t['brand'], t['model'], t['size']]
              .where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');
          result = 'Added $qty to existing $name (now ${t['quantity']})';
        }
      }

      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.toString() : 'Failed to save tyre.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Text(
                  _isEdit ? 'Edit Tyre' : 'Add Tyre',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _colorHeading),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: _colorSubtext),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Brand + Model
            Row(children: [
              Expanded(child: _field(_brandCtrl, 'Brand *', hint: 'e.g. MRF')),
              const SizedBox(width: 12),
              Expanded(child: _field(_modelCtrl, 'Model', hint: 'e.g. ZVTS')),
            ]),
            const SizedBox(height: 12),

            // Pattern / design
            _field(_patternCtrl, 'Pattern / Design', hint: 'e.g. Wanderer Street'),
            const SizedBox(height: 12),

            // Size + Vehicle Type
            Row(children: [
              Expanded(child: _field(_sizeCtrl, 'Size *', hint: 'e.g. 195/65R15')),
              const SizedBox(width: 12),
              Expanded(child: _field(_vTypeCtrl, 'Vehicle Type', hint: 'car / bike')),
            ]),
            const SizedBox(height: 12),

            // Qty + Price
            Row(children: [
              Expanded(child: _field(_qtyCtrl, 'Quantity', hint: '0', isNumber: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(_priceCtrl, 'Price (₹)', hint: '0', isDecimal: true)),
            ]),
            const SizedBox(height: 12),

            // Offer
            _field(_offerCtrl, 'Offer / Note', hint: 'e.g. Buy 2 Get 10% off'),
            if (!_isEdit) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _field(_dealerCtrl, 'Dealer', hint: 'optional')),
                const SizedBox(width: 12),
                Expanded(child: _field(_costCtrl, 'Cost price / tyre (₹)', hint: 'optional', isDecimal: true)),
              ]),
            ],
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(_isEdit ? 'Update Tyre' : 'Add to Stock',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    bool isNumber  = false,
    bool isDecimal = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : isNumber
              ? TextInputType.number
              : TextInputType.text,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: InputDecoration(
        labelText: label,
        hintText:  hint,
        hintStyle: const TextStyle(fontSize: 13, color: _colorSubtext),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _colorBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _colorBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _colorPrimary, width: 1.5)),
      ),
    );
  }
}


class _PurchaseHistoryScreen extends StatelessWidget {
  const _PurchaseHistoryScreen({required this.apiService});
  final ApiService apiService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tyres Bought (last 50)')),
      body: FutureBuilder<List<dynamic>>(
        future: apiService.getRecentTyrePurchases(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return const Center(child: Text('Failed to load purchases.'));
          final rows = snap.data ?? [];
          if (rows.isEmpty) return const Center(child: Text('No purchases logged yet.'));
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i] as Map;
              final d = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
              final cost = double.tryParse(r['unit_cost']?.toString() ?? '');
              return ListTile(
                title: Text([r['brand'], r['name'], r['size']]
                    .where((e) => e != null && e.toString().isNotEmpty).join(' ')),
                subtitle: Text([
                  if (d != null) '${d.day}/${d.month}/${d.year}',
                  if (r['dealer'] != null) r['dealer'].toString(),
                  if (cost != null) '₹${cost.toStringAsFixed(0)} each',
                ].join(' · ')),
                trailing: Text('×${r['quantity']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            },
          );
        },
      ),
    );
  }
}
