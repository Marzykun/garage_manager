import 'package:flutter/material.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary   = Color(0xFF2D3A4A);
const _colorHeading   = Color(0xFF1A2332);
const _colorSubtext   = Color(0xFF7A869A);
const _colorBodyText  = Color(0xFF4A5568);
const _colorBorder    = Color(0xFFE8EAED);
const _colorInputBg   = Color(0xFFF0F2F5);
const _colorSuccess   = Color(0xFF27AE60);

class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.apiService,
    required this.jobId,
    required this.serviceType,
    required this.vehicleReg,
    required this.customerName,
  });

  final ApiService apiService;
  final String jobId;
  final String serviceType;
  final String vehicleReg;
  final String customerName;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  bool _isSaving = false;
  bool _isLoading = true;
  List<dynamic> _records = [];
  String? _error;

  // Balancing fields
  final _flCtrl = TextEditingController();
  final _frCtrl = TextEditingController();
  final _rlCtrl = TextEditingController();
  final _rrCtrl = TextEditingController();
  String _roundType = 'before';

  // Alignment fields
  final _alignReportCtrl = TextEditingController();

  // Shared remarks / parts
  final _remarksCtrl = TextEditingController();
  final _partsCtrl   = TextEditingController();

  // Tyre change fields
  List<dynamic> _tyreStock  = [];
  bool _tyresLoading        = false;
  Map<String, dynamic>? _selectedTyre;
  int _tyreQty              = 1;
  final _tyreRemarksCtrl    = TextEditingController();

  bool get _isBalancing  => widget.serviceType == 'wheel_balancing';
  bool get _isAlignment  => widget.serviceType == 'wheel_alignment';
  bool get _isTyreChange => widget.serviceType == 'tyre_change';

  @override
  void initState() {
    super.initState();
    _loadRecords();
    if (_isTyreChange) _loadTyreStock();
  }

  @override
  void dispose() {
    _flCtrl.dispose(); _frCtrl.dispose();
    _rlCtrl.dispose(); _rrCtrl.dispose();
    _alignReportCtrl.dispose();
    _remarksCtrl.dispose(); _partsCtrl.dispose();
    _tyreRemarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      dynamic data;
      if (_isBalancing) {
        final resp = await widget.apiService.getBalancingByJob(widget.jobId);
        data = (resp is Map<String, dynamic>) ? resp['data'] : resp;
      } else if (_isAlignment) {
        final resp = await widget.apiService.getAlignmentByJob(widget.jobId);
        data = (resp is Map<String, dynamic>) ? resp['data'] : resp;
      } else if (_isTyreChange) {
        data = await widget.apiService.getTyreChangeByJob(widget.jobId);
      } else {
        final resp = await widget.apiService.getServiceDetailsByJob(widget.jobId);
        data = (resp is Map<String, dynamic>) ? resp['data'] : resp;
      }
      setState(() => _records = (data is List) ? data : []);
    } catch (e) {
      setState(() => _error = e is ApiException ? e.toString() : 'Failed to load records.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTyreStock() async {
    setState(() => _tyresLoading = true);
    try {
      final data = await widget.apiService.getTyres();
      if (mounted) setState(() => _tyreStock = data is List ? data : []);
    } catch (_) {
      // non-fatal — user will see empty dropdown
    } finally {
      if (mounted) setState(() => _tyresLoading = false);
    }
  }

  double? _parseWeight(String v) {
    final d = double.tryParse(v.trim());
    return (d != null && d > 0) ? d : null;
  }

  Future<void> _save() async {
    if (_isTyreChange) { _saveTyreChange(); return; }
    setState(() => _isSaving = true);
    try {
      if (_isBalancing) {
        await widget.apiService.saveBalancing(
          jobCardId: widget.jobId,
          flWeight:  _parseWeight(_flCtrl.text),
          frWeight:  _parseWeight(_frCtrl.text),
          rlWeight:  _parseWeight(_rlCtrl.text),
          rrWeight:  _parseWeight(_rrCtrl.text),
          remarks:   _remarksCtrl.text.trim(),
          roundType: _roundType,
        );
        _flCtrl.clear(); _frCtrl.clear(); _rlCtrl.clear(); _rrCtrl.clear();
      } else if (_isAlignment) {
        await widget.apiService.saveAlignment(
          jobCardId:       widget.jobId,
          alignmentReport: _alignReportCtrl.text.trim(),
          remarks:         _remarksCtrl.text.trim(),
        );
        _alignReportCtrl.clear();
      } else {
        await widget.apiService.saveServiceDetail(
          jobCardId:   widget.jobId,
          serviceType: widget.serviceType,
          remarks:     _remarksCtrl.text.trim(),
          partsUsed:   _partsCtrl.text.trim(),
        );
        _partsCtrl.clear();
      }
      _remarksCtrl.clear();
      _showSnack('Saved successfully.');
      await _loadRecords();
    } catch (e) {
      _showSnack(e is ApiException ? e.toString() : 'Failed to save.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveTyreChange() async {
    if (_selectedTyre == null) { _showSnack('Please select a tyre.'); return; }
    final stock = int.tryParse(_selectedTyre!['quantity']?.toString() ?? '0') ?? 0;
    if (stock < _tyreQty) { _showSnack('Only $stock in stock.'); return; }

    setState(() => _isSaving = true);
    try {
      await widget.apiService.saveTyreChange(
        jobCardId: widget.jobId,
        tyreId:    _selectedTyre!['id'].toString(),
        quantity:  _tyreQty,
        remarks:   _tyreRemarksCtrl.text.trim(),
      );
      setState(() { _selectedTyre = null; _tyreQty = 1; });
      _tyreRemarksCtrl.clear();
      _showSnack('Tyre change saved.');
      await _loadRecords();
      await _loadTyreStock(); // refresh stock counts
    } catch (e) {
      _showSnack(e is ApiException ? e.toString() : 'Failed to save tyre change.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _title {
    switch (widget.serviceType) {
      case 'wheel_balancing': return 'Wheel Balancing';
      case 'wheel_alignment': return 'Wheel Alignment';
      case 'tyre_change':     return 'Tyre Change';
      case 'car_wash':        return 'Car Wash';
      case 'water_wash':      return 'Water Wash';
      case 'full_service':    return 'Full Service';
      default:                return 'Service Details';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _JobInfoCard(vehicleReg: widget.vehicleReg, customerName: widget.customerName, serviceType: _title),
          const SizedBox(height: 16),
          _buildForm(),
          const SizedBox(height: 24),
          _buildRecordsList(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Log Entry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
          const SizedBox(height: 16),
          if (_isBalancing) ..._balancingFields(),
          if (_isAlignment) ..._alignmentFields(),
          if (!_isBalancing && !_isAlignment && !_isTyreChange) ..._genericFields(),
          if (_isTyreChange) ..._tyreChangeFields(),
          if (!_isTyreChange) ...[
            const SizedBox(height: 16),
            _remarksField(),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Save Entry'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _balancingFields() => [
    // Round type toggle
    Row(children: ['before', 'after'].map((type) {
      final sel = _roundType == type;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: () => setState(() => _roundType = type),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? _colorPrimary : _colorInputBg,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Text(
              type == 'before' ? 'Before' : 'After',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : _colorBodyText),
            ),
          ),
        ),
      );
    }).toList()),
    const SizedBox(height: 16),
    // Weight grid
    const _FieldLabel('Weights (grams)'),
    const SizedBox(height: 8),
    Row(children: [
      Expanded(child: _WeightField(ctrl: _flCtrl, label: 'FL')),
      const SizedBox(width: 10),
      Expanded(child: _WeightField(ctrl: _frCtrl, label: 'FR')),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _WeightField(ctrl: _rlCtrl, label: 'RL')),
      const SizedBox(width: 10),
      Expanded(child: _WeightField(ctrl: _rrCtrl, label: 'RR')),
    ]),
    const SizedBox(height: 16),
  ];

  List<Widget> _alignmentFields() => [
    const _FieldLabel('Alignment Report'),
    const SizedBox(height: 8),
    TextField(
      controller: _alignReportCtrl,
      maxLines: 4,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: const InputDecoration(
        hintText: 'Enter camber, toe, caster readings…',
        hintStyle: TextStyle(fontSize: 13, color: _colorSubtext),
      ),
    ),
    const SizedBox(height: 16),
  ];

  List<Widget> _genericFields() => [
    const _FieldLabel('Parts Used (optional)'),
    const SizedBox(height: 8),
    TextField(
      controller: _partsCtrl,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: const InputDecoration(hintText: 'e.g. Filter, oil, coolant…',
          hintStyle: TextStyle(fontSize: 13, color: _colorSubtext)),
    ),
    const SizedBox(height: 16),
  ];

  List<Widget> _tyreChangeFields() {
    if (_tyresLoading) {
      return [const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))];
    }

    final inStock = _tyreStock.where((t) {
      final qty = int.tryParse(t['quantity']?.toString() ?? '0') ?? 0;
      return qty > 0;
    }).toList();

    if (inStock.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F2),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            border: Border.all(color: const Color(0xFFFFE0B2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFE67E22)),
            SizedBox(width: 8),
            Expanded(child: Text('No tyres in stock. Add stock via Settings → Tyre Stock.',
                style: TextStyle(fontSize: 13, color: Color(0xFFE67E22)))),
          ]),
        ),
        const SizedBox(height: 16),
      ];
    }

    return [
      const _FieldLabel('Select Tyre from Stock'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _colorInputBg,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Map<String, dynamic>>(
            value: _selectedTyre,
            isExpanded: true,
            hint: const Text('Choose tyre…', style: TextStyle(fontSize: 14, color: _colorSubtext)),
            items: inStock.map((t) {
              final label = [t['brand'], t['model'], t['size']].where((v) => v != null && v.toString().isNotEmpty).join(' ');
              final qty = t['quantity']?.toString() ?? '0';
              return DropdownMenuItem<Map<String, dynamic>>(
                value: t as Map<String, dynamic>,
                child: Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: _colorHeading))),
                  Text('Qty: $qty', style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                ]),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedTyre = val),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const _FieldLabel('Number of Tyres'),
      const SizedBox(height: 8),
      Row(children: [
        _QtyButton(
          icon: Icons.remove,
          onTap: () { if (_tyreQty > 1) setState(() => _tyreQty--); },
        ),
        const SizedBox(width: 16),
        Text('$_tyreQty', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _colorHeading)),
        const SizedBox(width: 16),
        _QtyButton(
          icon: Icons.add,
          onTap: () {
            final max = int.tryParse(_selectedTyre?['quantity']?.toString() ?? '4') ?? 4;
            if (_tyreQty < max) setState(() => _tyreQty++);
          },
        ),
        if (_selectedTyre != null) ...[
          const SizedBox(width: 12),
          Text('(${_selectedTyre!['quantity']} in stock)',
              style: const TextStyle(fontSize: 12, color: _colorSubtext)),
        ],
      ]),
      const SizedBox(height: 16),
      const _FieldLabel('Remarks (optional)'),
      const SizedBox(height: 8),
      TextField(
        controller: _tyreRemarksCtrl,
        maxLines: 2,
        style: const TextStyle(fontSize: 14, color: _colorHeading),
        decoration: const InputDecoration(
          hintText: 'e.g. All 4 tyres replaced…',
          hintStyle: TextStyle(fontSize: 13, color: _colorSubtext),
        ),
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget _remarksField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _FieldLabel('Remarks (optional)'),
      const SizedBox(height: 8),
      TextField(
        controller: _remarksCtrl,
        maxLines: 2,
        style: const TextStyle(fontSize: 14, color: _colorHeading),
        decoration: const InputDecoration(
          hintText: 'Any observations or notes…',
          hintStyle: TextStyle(fontSize: 13, color: _colorSubtext),
        ),
      ),
    ],
  );

  Widget _buildRecordsList() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
      );
    }
    if (_records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('No entries yet.', style: TextStyle(color: _colorSubtext, fontSize: 14)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_records.length} saved ${_records.length == 1 ? 'entry' : 'entries'}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorSubtext)),
        const SizedBox(height: 10),
        ..._records.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RecordCard(record: r, isBalancing: _isBalancing, isAlignment: _isAlignment, isTyreChange: _isTyreChange),
        )),
      ],
    );
  }
}

// ─── Job info header ──────────────────────────────────────────────────────────

class _JobInfoCard extends StatelessWidget {
  const _JobInfoCard({required this.vehicleReg, required this.customerName, required this.serviceType});
  final String vehicleReg;
  final String customerName;
  final String serviceType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: const BoxDecoration(color: Color(0xFFF0F2F5), shape: BoxShape.circle),
          child: const Icon(Icons.directions_car_rounded, size: 22, color: _colorPrimary),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(vehicleReg, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _colorHeading, letterSpacing: 0.4)),
          Text(customerName, style: const TextStyle(fontSize: 13, color: _colorBodyText)),
          Text(serviceType, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
        ]),
      ]),
    );
  }
}

// ─── Record card ──────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.isBalancing, required this.isAlignment, this.isTyreChange = false});
  final dynamic record;
  final bool isBalancing;
  final bool isAlignment;
  final bool isTyreChange;

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw.toString()).toLocal();
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return raw.toString(); }
  }

  @override
  Widget build(BuildContext context) {
    final m = record as Map<String, dynamic>;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(12)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_outline_rounded, size: 14, color: _colorSuccess),
            const SizedBox(width: 6),
            Text(_formatDate(m['created_at']), style: const TextStyle(fontSize: 12, color: _colorSubtext)),
            if (isBalancing && m['round_type'] != null) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: m['round_type'] == 'after' ? const Color(0x1A27AE60) : const Color(0x1AE67E22),
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                ),
                child: Text(
                  m['round_type'].toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: m['round_type'] == 'after' ? _colorSuccess : const Color(0xFFE67E22),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          if (isBalancing)   _balancingBody(m),
          if (isAlignment)   _alignmentBody(m),
          if (isTyreChange)  _tyreChangeBody(m),
          if (!isBalancing && !isAlignment && !isTyreChange) _genericBody(m),
          if (m['remarks'] != null && m['remarks'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Remarks: ${m['remarks']}', style: const TextStyle(fontSize: 12, color: _colorSubtext)),
          ],
        ],
      ),
    );
  }

  Widget _balancingBody(Map<String, dynamic> m) {
    String fmt(dynamic v) => v != null ? '${v}g' : '—';
    return Row(children: [
      _WeightDisplay(label: 'FL', value: fmt(m['fl_weight'])),
      const SizedBox(width: 12),
      _WeightDisplay(label: 'FR', value: fmt(m['fr_weight'])),
      const SizedBox(width: 12),
      _WeightDisplay(label: 'RL', value: fmt(m['rl_weight'])),
      const SizedBox(width: 12),
      _WeightDisplay(label: 'RR', value: fmt(m['rr_weight'])),
    ]);
  }

  Widget _alignmentBody(Map<String, dynamic> m) {
    final report = m['alignment_report']?.toString() ?? '';
    if (report.isEmpty) return const SizedBox.shrink();
    return Text(report, style: const TextStyle(fontSize: 13, color: _colorBodyText));
  }

  Widget _genericBody(Map<String, dynamic> m) {
    final parts = m['parts_used']?.toString() ?? '';
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text('Parts: $parts', style: const TextStyle(fontSize: 13, color: _colorBodyText));
  }

  Widget _tyreChangeBody(Map<String, dynamic> m) {
    final brand = m['brand']?.toString() ?? '';
    final model = m['model']?.toString() ?? '';
    final size  = m['size']?.toString()  ?? '';
    final label = [brand, model, size].where((v) => v.isNotEmpty).join(' ');
    final qty   = m['quantity']?.toString() ?? '1';
    final price = m['price'];

    return Row(children: [
      const Icon(Icons.tire_repair, size: 16, color: _colorPrimary),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading))),
      Text('×$qty', style: const TextStyle(fontSize: 13, color: _colorBodyText)),
      if (price != null) ...[
        const SizedBox(width: 8),
        Text('₹$price', style: const TextStyle(fontSize: 12, color: _colorSubtext)),
      ],
    ]);
  }
}

class _WeightDisplay extends StatelessWidget {
  const _WeightDisplay({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: _colorSubtext, fontWeight: FontWeight.w500)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _colorHeading)),
    ]);
  }
}

// ─── Small reusable widgets ───────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _colorBodyText));
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: _colorInputBg,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Icon(icon, size: 20, color: _colorPrimary),
      ),
    );
  }
}

class _WeightField extends StatelessWidget {
  const _WeightField({required this.ctrl, required this.label});
  final TextEditingController ctrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 15, color: _colorHeading),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'g',
        suffixStyle: const TextStyle(fontSize: 13, color: _colorSubtext),
      ),
    );
  }
}
