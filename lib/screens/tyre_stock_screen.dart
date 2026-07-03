import 'package:flutter/material.dart';
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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TyreForm(apiService: widget.apiService, existing: tyre),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Tyre Stock'),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
        actions: [
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
                Text(size, style: const TextStyle(fontSize: 13, color: _colorSubtext)),
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
  final _sizeCtrl   = TextEditingController();
  final _vTypeCtrl  = TextEditingController();
  final _qtyCtrl    = TextEditingController();
  final _priceCtrl  = TextEditingController();
  final _offerCtrl  = TextEditingController();
  bool  _saving     = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.existing!;
      _brandCtrl.text  = t['brand']?.toString()         ?? '';
      _modelCtrl.text  = t['model']?.toString()         ?? '';
      _sizeCtrl.text   = t['size']?.toString()          ?? '';
      _vTypeCtrl.text  = t['vehicle_type']?.toString()  ?? '';
      _qtyCtrl.text    = (t['quantity'] ?? 0).toString();
      _priceCtrl.text  = t['price'] != null ? double.tryParse(t['price'].toString())?.toStringAsFixed(0) ?? '' : '';
      _offerCtrl.text  = t['offer']?.toString()         ?? '';
    }
  }

  @override
  void dispose() {
    _brandCtrl.dispose(); _modelCtrl.dispose(); _sizeCtrl.dispose();
    _vTypeCtrl.dispose(); _qtyCtrl.dispose(); _priceCtrl.dispose();
    _offerCtrl.dispose();
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

      if (_isEdit) {
        await widget.apiService.updateTyre(
          widget.existing!['id'].toString(),
          brand:       brand,
          size:        size,
          model:       _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
          vehicleType: _vTypeCtrl.text.trim().isEmpty ? null : _vTypeCtrl.text.trim(),
          quantity:    qty,
          price:       price,
          offer:       _offerCtrl.text.trim().isEmpty ? null : _offerCtrl.text.trim(),
        );
      } else {
        await widget.apiService.addTyre(
          brand:       brand,
          size:        size,
          model:       _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
          vehicleType: _vTypeCtrl.text.trim().isEmpty ? null : _vTypeCtrl.text.trim(),
          quantity:    qty,
          price:       price,
          offer:       _offerCtrl.text.trim().isEmpty ? null : _offerCtrl.text.trim(),
        );
      }

      if (mounted) Navigator.pop(context, true);
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
