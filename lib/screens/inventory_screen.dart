import 'package:flutter/material.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder  = Color(0xFFE8EAED);
const _colorGreen   = Color(0xFF2E7D32);
const _colorRed     = Color(0xFFE53935);
const _colorAmber   = Color(0xFFF59E0B);

const _categories = ['wheel_weight', 'foam', 'lubricant', 'other'];
const _categoryLabels = {
  'tyre':         'Tyre',
  'wheel_weight': 'Wheel Weight',
  'foam':         'Foam',
  'lubricant':    'Lubricant',
  'other':        'Other',
};
const _categoryIcons = {
  'tyre':         Icons.tire_repair,
  'wheel_weight': Icons.fitness_center,
  'foam':         Icons.bubble_chart_outlined,
  'lubricant':    Icons.opacity,
  'other':        Icons.inventory_2_outlined,
};

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<dynamic> _items    = [];
  bool _loading           = true;
  String? _error;
  String? _filterCategory; // null = all
  List<dynamic> _dups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.apiService.getInventory(category: _filterCategory);
      List<dynamic> dups = [];
      try { dups = await widget.apiService.getInventoryDuplicates(); } catch (_) {}
      if (mounted) setState(() { _items = data is List ? data : []; _dups = dups; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.toString() : 'Failed to load inventory.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Item?'),
        content: Text('Remove "${item['name']}" from inventory?'),
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
      await widget.apiService.deleteInventoryItem(item['id'].toString());
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.toString() : 'Failed to remove item.')),
        );
      }
    }
  }

  Future<void> _mergeDuplicates() async {
    String qtys(Map g) => (g['rows'] as List).map((r) => r['quantity']).join(' + ');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Merge duplicate items?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _colorHeading)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final g in _dups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${g['name']}: ${qtys(g as Map)} → ${g['merged_quantity']}',
                          style: const TextStyle(fontSize: 14, color: _colorHeading)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Quantities are added together and the extra cards are removed. This cannot be undone.',
                style: TextStyle(fontSize: 12, color: _colorRed)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: _colorPrimary, foregroundColor: Colors.white),
                  child: const Text('Merge'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await widget.apiService.mergeInventoryDuplicates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Merged ${r['merged_groups']} item(s), removed ${r['removed_rows']} duplicate card(s)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e is ApiException ? e.toString() : 'Failed to merge.')));
      }
    }
    _load();
  }

  void _openForm({Map<String, dynamic>? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ItemForm(apiService: widget.apiService, existing: item),
    );
    if (saved == true) _load();
  }

  List<dynamic> get _lowStock => _items.where((i) {
    final qty = int.tryParse(i['quantity']?.toString() ?? '0') ?? 0;
    final min = int.tryParse(i['min_stock']?.toString() ?? '5') ?? 5;
    return qty <= min;
  }).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Parts Inventory'),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
        // App theme sets a dark title/icon style; override it on this dark bar
        titleTextStyle: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_dups.isNotEmpty)
            Badge(
              label: Text('${_dups.length}'),
              offset: const Offset(-6, 6),
              child: IconButton(
                tooltip: 'Merge duplicates',
                icon: const Icon(Icons.merge_type),
                onPressed: _mergeDuplicates,
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: _colorRed)))
              : Column(
                  children: [
                    _buildFilterBar(),
                    Expanded(child: _buildBody()),
                  ],
                ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 44,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _FilterChip(label: 'All', selected: _filterCategory == null, onTap: () { setState(() => _filterCategory = null); _load(); }),
          ..._categories.map((c) => _FilterChip(
            label: _categoryLabels[c]!,
            selected: _filterCategory == c,
            onTap: () { setState(() => _filterCategory = c); _load(); },
          )),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      return const Center(
        child: Text('No items in inventory.\nTap + to add some.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _colorSubtext, fontSize: 15)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_lowStock.isNotEmpty && _filterCategory == null) ...[
            _SectionHeader(label: '⚠ Low Stock (${_lowStock.length})', color: _colorAmber),
            ..._lowStock.map((i) => _ItemCard(
              item: i as Map<String, dynamic>,
              onEdit: () => _openForm(item: i),
              onDelete: () => _delete(i),
            )),
            const SizedBox(height: 8),
            const _SectionHeader(label: 'All Items', color: _colorPrimary),
          ],
          ..._items.map((i) => _ItemCard(
            item: i as Map<String, dynamic>,
            onEdit: () => _openForm(item: i),
            onDelete: () => _delete(i),
          )),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? _colorPrimary : const Color(0xFFF0F4F8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _colorSubtext)),
      ),
    );
  }
}

// ── Item card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name     = item['name']?.toString()     ?? '';
    final category = item['category']?.toString() ?? 'other';
    final qty      = int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
    final unit     = item['unit']?.toString()     ?? 'pcs';
    final minStock = int.tryParse(item['min_stock']?.toString() ?? '5') ?? 5;
    final isLow    = qty <= minStock;
    final price    = double.tryParse(item['price']?.toString() ?? '') ?? 0;
    final stockColor = qty == 0 ? _colorRed : isLow ? _colorAmber : _colorGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLow ? _colorAmber.withValues(alpha: 0.4) : _colorBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10)),
            child: Icon(_categoryIcons[category] ?? Icons.inventory_2_outlined, size: 22, color: _colorPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _colorHeading)),
                const SizedBox(height: 3),
                Text(_categoryLabels[category] ?? category,
                    style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                const SizedBox(height: 6),
                Row(children: [
                  _Chip(label: '$qty $unit', color: stockColor),
                  const SizedBox(width: 8),
                  _Chip(label: 'Min: $minStock', color: _colorSubtext),
                  if (price > 0) ...[
                    const SizedBox(width: 8),
                    _Chip(label: '₹${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)} each', color: _colorPrimary),
                  ],
                ]),
              ],
            ),
          ),
          Column(children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20, color: _colorSubtext),
              onPressed: onEdit, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
            const SizedBox(height: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: _colorRed),
              onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
          ]),
        ],
      ),
    );
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ── Add / Edit form ───────────────────────────────────────────────────────────

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.apiService, this.existing});
  final ApiService apiService;
  final Map<String, dynamic>? existing;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  final _nameCtrl     = TextEditingController();
  final _qtyCtrl      = TextEditingController();
  final _unitCtrl     = TextEditingController();
  final _minCtrl      = TextEditingController();
  final _priceCtrl    = TextEditingController();
  String _category    = 'other';
  bool   _saving      = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final e = widget.existing!;
      _nameCtrl.text = e['name']?.toString()     ?? '';
      _qtyCtrl.text  = (e['quantity'] ?? 0).toString();
      _unitCtrl.text = e['unit']?.toString()     ?? 'pcs';
      _minCtrl.text  = (e['min_stock'] ?? 5).toString();
      _category      = e['category']?.toString() ?? 'other';
      final p = double.tryParse(e['price']?.toString() ?? '') ?? 0;
      _priceCtrl.text = p > 0 ? p.toString().replaceFirst(RegExp(r'\.0$'), '') : '';
    } else {
      _qtyCtrl.text = '0';
      _unitCtrl.text = 'pcs';
      _minCtrl.text = '5';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _qtyCtrl.dispose();
    _unitCtrl.dispose(); _minCtrl.dispose(); _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { _snack('Name is required.'); return; }

    final priceText = _priceCtrl.text.trim();
    final price = priceText.isEmpty ? 0.0 : double.tryParse(priceText);
    if (price == null || price < 0) { _snack('Enter a valid price.'); return; }

    setState(() => _saving = true);
    try {
      final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
      final min = int.tryParse(_minCtrl.text.trim()) ?? 5;
      final unit = _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim();

      if (_isEdit) {
        final res = await widget.apiService.updateInventoryItem(
          widget.existing!['id'].toString(),
          name: name, category: _category, quantity: qty, unit: unit, minStock: min, price: price,
        );
        if (res is Map && res['merged'] == true && mounted) {
          final d = res['data'] as Map?;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Merged into existing ${d?['name'] ?? name} (now ${d?['quantity']})')));
        }
      } else {
        final res = await widget.apiService.addInventoryItem(
          name: name, category: _category, quantity: qty, unit: unit, minStock: min, price: price,
        );
        if (res is Map && res['merged'] == true && mounted) {
          // Already in stock: backend added to the existing card instead of making a new one
          final now = (res['data'] as Map?)?['quantity'];
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Added $qty to existing $name (now $now)')));
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Failed to save.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
            Row(children: [
              Text(_isEdit ? 'Edit Item' : 'Add Item',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _colorHeading)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, color: _colorSubtext), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),

            // Name
            _field(_nameCtrl, 'Item Name *', hint: 'e.g. Wheel Weight 5g'),
            const SizedBox(height: 12),

            // Category
            const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _categories.map((c) {
                final sel = _category == c;
                return GestureDetector(
                  onTap: () => setState(() => _category = c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? _colorPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: sel ? _colorPrimary : _colorBorder),
                    ),
                    child: Text(_categoryLabels[c]!,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : _colorSubtext)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Qty + Unit
            Row(children: [
              Expanded(child: _field(_qtyCtrl, 'Quantity', hint: '0', isNumber: true)),
              const SizedBox(width: 12),
              Expanded(child: _field(_unitCtrl, 'Unit', hint: 'pcs / kg / L')),
            ]),
            const SizedBox(height: 12),

            // Min stock
            _field(_minCtrl, 'Low Stock Alert (min qty)', hint: '5', isNumber: true),
            const SizedBox(height: 12),
            _field(_priceCtrl, 'Price per unit (₹)', hint: 'optional', isNumber: true),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _colorPrimary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(_isEdit ? 'Update Item' : 'Add to Inventory',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {String? hint, bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: _colorSubtext),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _colorBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _colorBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _colorPrimary, width: 1.5)),
      ),
    );
  }
}
