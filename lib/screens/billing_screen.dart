import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garage_manager/services/api_service.dart';

const double _kGstRate = 0.18; // 18% GST as per client spec

class BillingScreen extends StatefulWidget {
  const BillingScreen({
    super.key,
    required this.apiService,
    required this.jobId,
  });

  final ApiService apiService;
  final String jobId;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isMarkingPaid = false;
  bool _isMarkingDone = false;
  Map<String, dynamic> _jobData = {};
  String? _errorMessage;
  Map<String, dynamic>? _billPreview;
  String _selectedPaymentMethod = 'cash';

  // Parts priced automatically from the job's logged tyre changes
  List<String> _loggedPartsLines = [];

  final TextEditingController _labourCtrl   = TextEditingController(text: '0');
  final TextEditingController _partsCtrl    = TextEditingController(text: '0');
  final TextEditingController _discountCtrl = TextEditingController(text: '0');
  final TextEditingController _notesCtrl    = TextEditingController();

  double get _labour   => double.tryParse(_labourCtrl.text.trim())   ?? 0;
  double get _parts    => double.tryParse(_partsCtrl.text.trim())    ?? 0;
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;
  double get _subTotal => _labour + _parts;
  double get _gstAmount => _subTotal * _kGstRate;
  double get _total     => _subTotal + _gstAmount - _discount;

  @override
  void initState() {
    super.initState();
    _loadJobDetails();
  }

  @override
  void dispose() {
    _labourCtrl.dispose();
    _partsCtrl.dispose();
    _discountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadJobDetails() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      // Load job details
      final response = await widget.apiService.getJob(widget.jobId);
      if (response is Map<String, dynamic>) {
        final job = (response['data'] is Map<String, dynamic>)
            ? response['data'] as Map<String, dynamic>
            : response;
        setState(() {
          _jobData = job;
          _notesCtrl.text = job['notes']?.toString() ?? '';
        });
      }

      // Also check if an invoice already exists — pre-populate preview
      try {
        final billResponse = await widget.apiService.getBill(widget.jobId);
        if (billResponse is Map<String, dynamic>) {
          final inv = (billResponse['data'] is Map<String, dynamic>)
              ? billResponse['data'] as Map<String, dynamic>
              : billResponse;
          if (inv['id'] != null) {
            final labour = double.tryParse(inv['labour_charge']?.toString() ?? '0') ?? 0;
            final parts  = double.tryParse(inv['parts_charge']?.toString()  ?? '0') ?? 0;
            final disc   = double.tryParse(inv['discount']?.toString()       ?? '0') ?? 0;
            _labourCtrl.text   = labour.toStringAsFixed(0);
            _partsCtrl.text    = parts.toStringAsFixed(0);
            _discountCtrl.text = disc.toStringAsFixed(0);
            setState(() {
              _billPreview = {
                'customerName':   inv['customer_name'] ?? _customerName,
                'vehicleReg':     inv['vehicle_number'] ?? _vehicleNumber,
                'services':       [inv['service_type'] ?? ''],
                'labour':         labour,
                'parts':          parts,
                'gst':            double.tryParse(inv['gst_amount']?.toString() ?? '0') ?? 0,
                'discount':       disc,
                'total':          double.tryParse(inv['total_amount']?.toString() ?? '0') ?? 0,
                'billId':         inv['id'],
                'date':           inv['created_at']?.toString(),
                'phone':          inv['customer_phone'],
                'payment_status': inv['payment_status']?.toString() ?? 'pending',
                'payment_method': inv['payment_method']?.toString(),
              };
            });
          }
        }
      } catch (_) {
        // No existing invoice — that's fine, user will generate one
      }

      // Auto-price parts from the job's logged tyre changes (fixed rates in tyre stock).
      // Inventory parts are free-text with no price column, so tyres are the
      // only auto-priceable part today.
      try {
        final tc = await widget.apiService.getTyreChangeByJob(widget.jobId);
        final rows = (tc is Map<String, dynamic>)
            ? (tc['data'] as List? ?? [])
            : (tc as List? ?? []);
        double total = 0;
        final lines = <String>[];
        for (final r in rows) {
          final qty   = int.tryParse(r['quantity']?.toString() ?? '') ?? 0;
          final price = double.tryParse(r['price']?.toString() ?? '') ?? 0;
          if (qty <= 0 || price <= 0) continue;
          total += qty * price;
          lines.add('${r['brand'] ?? ''} ${r['size'] ?? ''} ×$qty = ₹${(qty * price).toStringAsFixed(0)}');
        }
        if (total > 0) {
          _loggedPartsLines = lines;
          // Prefill only when there's no saved invoice and the field is untouched
          if (_billPreview == null && (double.tryParse(_partsCtrl.text.trim()) ?? 0) == 0) {
            _partsCtrl.text = total.toStringAsFixed(0);
          }
        }
      } catch (_) {
        // Tyre log unavailable — leave parts manual
      }
    } catch (error) {
      setState(() {
        _errorMessage = error is ApiException ? error.toString() : 'Unable to load job details.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _vehicleNumber =>
      _jobData['vehicle_number']?.toString() ?? _jobData['vehicleReg']?.toString() ?? 'Unknown';
  String get _customerName =>
      _jobData['customer_name']?.toString() ?? _jobData['customerName']?.toString() ?? 'Unknown';
  String get _jobStatus => _jobData['status']?.toString() ?? '';

  String? get _customerPhone =>
      _jobData['customer_phone']?.toString() ?? _jobData['phone']?.toString();

  List<String> get _services {
    // Backend returns service_type as a snake_case enum string (e.g. "wheel_alignment")
    final st = _jobData['service_type']?.toString();
    if (st != null && st.isNotEmpty) {
      return [st.replaceAll('_', ' ').split(' ').map((w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ')];
    }
    // Fallback: legacy 'services' array / comma string
    final s = _jobData['services'];
    if (s is List) return s.map((e) => e.toString()).toList();
    if (s is String) return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [];
  }

  Future<void> _generateBill() async {
    if (_total <= 0) {
      _showSnack('Please enter labour or parts charges.');
      return;
    }
    setState(() { _isGenerating = true; _errorMessage = null; });
    try {
      final existingId = _billPreview?['billId']?.toString();
      dynamic response;

      if (existingId != null) {
        // Invoice already exists — update it
        response = await widget.apiService.updateInvoice(
          existingId,
          labourCharge: _labour,
          partsCharge:  _parts,
          discount:     _discount,
        );
      } else {
        // Create new invoice
        response = await widget.apiService.generateBill(
          widget.jobId,
          labourCharge: _labour,
          partsCharge:  _parts,
          discount:     _discount,
          notes:        _notesCtrl.text.trim(),
        );
      }

      final preview = <String, dynamic>{
        'customerName':   _customerName,
        'vehicleReg':     _vehicleNumber,
        'services':       _services,
        'labour':         _labour,
        'parts':          _parts,
        'gst':            _gstAmount,
        'discount':       _discount,
        'total':          _total,
        'date':           DateTime.now().toIso8601String(),
        'phone':          _customerPhone,
        'payment_status': _billPreview?['payment_status'] ?? 'pending',
        'payment_method': _billPreview?['payment_method'],
      };

      if (response is Map<String, dynamic>) {
        final data = response['data'] is Map ? response['data'] as Map<String, dynamic> : response;
        preview['billId']         = data['id'] ?? existingId;
        preview['total']          = data['total_amount'] ?? data['total'] ?? data['amount'] ?? _total;
        preview['date']           = data['created_at']?.toString() ?? preview['date'];
        preview['payment_status'] = data['payment_status']?.toString() ?? preview['payment_status'];
        preview['payment_method'] = data['payment_method']?.toString() ?? preview['payment_method'];
      }

      setState(() => _billPreview = preview);
      _showSnack(existingId != null ? 'Invoice updated.' : 'Invoice created.');
    } catch (error) {
      setState(() {
        _errorMessage = error is ApiException ? error.toString() : 'Unable to save invoice.';
      });
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _markAsPaid() async {
    final invoiceId = _billPreview?['billId']?.toString();
    if (invoiceId == null) { _showSnack('Generate the invoice first.'); return; }

    setState(() => _isMarkingPaid = true);
    try {
      final response = await widget.apiService.markInvoiceAsPaid(invoiceId, _selectedPaymentMethod);
      final data = (response is Map<String, dynamic>)
          ? (response['data'] is Map ? response['data'] as Map<String, dynamic> : response)
          : <String, dynamic>{};
      setState(() {
        _billPreview!['payment_status'] = 'paid';
        _billPreview!['payment_method'] = data['payment_method']?.toString() ?? _selectedPaymentMethod;
      });
      _showSnack('Payment recorded — ₹${_billPreview!['total']} via ${_paymentLabel(_selectedPaymentMethod)}.');
    } catch (e) {
      _showSnack(e is ApiException ? e.toString() : 'Failed to record payment.');
    } finally {
      if (mounted) setState(() => _isMarkingPaid = false);
    }
  }

  Future<void> _markAsDone() async {
    final invoiceId = _billPreview?['billId']?.toString();
    if (invoiceId == null) { _showSnack('Generate the invoice first.'); return; }

    setState(() => _isMarkingDone = true);
    try {
      await widget.apiService.completeJob(widget.jobId);
      try {
        await widget.apiService.sendInvoiceWhatsApp(invoiceId);
      } catch (_) {
        // Job completion succeeded even if the bill message failed to send.
      }
      setState(() => _jobData['status'] = 'completed');
      _showSnack('Job marked as done — customer notified on WhatsApp with the bill.');
    } catch (e) {
      _showSnack(e is ApiException ? e.toString() : 'Failed to mark job as done.');
    } finally {
      if (mounted) setState(() => _isMarkingDone = false);
    }
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':        return 'Cash';
      case 'upi':         return 'UPI';
      case 'card':        return 'Card';
      case 'net_banking': return 'Net Banking';
      default:            return method;
    }
  }

  Future<void> _shareBill() async {
    if (_billPreview == null) return;
    final phone = _customerPhone;
    if (phone == null || phone.isEmpty) return;

    final total = _billPreview!['total'];
    final message = Uri.encodeComponent(
      'Garage Manager — Invoice\n'
      'Customer: $_customerName\n'
      'Vehicle: $_vehicleNumber\n'
      'Services: ${_services.join(', ')}\n'
      'Labour: ₹${_labour.toStringAsFixed(2)}\n'
      'Parts: ₹${_parts.toStringAsFixed(2)}\n'
      'GST (18%): ₹${_gstAmount.toStringAsFixed(2)}\n'
      '${_discount > 0 ? 'Discount: ₹${_discount.toStringAsFixed(2)}\n' : ''}'
      'Total: ₹${total is num ? total.toDouble().toStringAsFixed(2) : total}',
    );

    final uri = Uri.parse('https://wa.me/$phone?text=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('Unable to open WhatsApp.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Generate Invoice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_errorMessage != null) ...[
            _ErrorTile(message: _errorMessage!),
            const SizedBox(height: 16),
          ],

          // ── Job info ──────────────────────────────────────────────────────
          _SectionTitle('Job Details'),
          const SizedBox(height: 8),
          _InfoRow('Vehicle',  _vehicleNumber),
          _InfoRow('Customer', _customerName),
          if (_services.isNotEmpty)
            _InfoRow('Services', _services.join(', ')),
          const SizedBox(height: 20),

          // ── Charges input ─────────────────────────────────────────────────
          _SectionTitle('Charges'),
          const SizedBox(height: 12),
          _AmountField(ctrl: _labourCtrl,   label: 'Labour Charge (₹)',  onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          _AmountField(ctrl: _partsCtrl,    label: 'Parts Charge (₹)',   onChanged: (_) => setState(() {})),
          if (_loggedPartsLines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'From job log: ${_loggedPartsLines.join(', ')}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A869A)),
              ),
            ),
          const SizedBox(height: 12),
          _AmountField(ctrl: _discountCtrl, label: 'Discount (₹)',       onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),

          // ── Live GST summary ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EAED)),
            ),
            child: Column(
              children: [
                _CalcRow('Labour + Parts',    '₹${_subTotal.toStringAsFixed(2)}',  bold: false),
                _CalcRow('GST (18%)',          '₹${_gstAmount.toStringAsFixed(2)}', bold: false),
                if (_discount > 0)
                  _CalcRow('Discount',         '−₹${_discount.toStringAsFixed(2)}', bold: false),
                const Divider(height: 16),
                _CalcRow('Total',              '₹${_total.toStringAsFixed(2)}',    bold: true),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Notes ─────────────────────────────────────────────────────────
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          // ── Generate button ───────────────────────────────────────────────
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isGenerating ? null : _generateBill,
              child: _isGenerating
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : Text(_billPreview != null ? 'Update Invoice' : 'Generate Invoice'),
            ),
          ),

          // ── Bill preview + payment ────────────────────────────────────────
          if (_billPreview != null) ...[
            const SizedBox(height: 32),
            _SectionTitle('Invoice'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EAED)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Paid badge
                  if (_billPreview!['payment_status'] == 'paid') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x1A27AE60),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF27AE60)),
                        const SizedBox(width: 6),
                        Text(
                          'PAID · ${_paymentLabel(_billPreview!['payment_method']?.toString() ?? '')}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF27AE60)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _InfoRow('Customer', _billPreview!['customerName']?.toString() ?? ''),
                  _InfoRow('Vehicle',  _billPreview!['vehicleReg']?.toString()  ?? ''),
                  _InfoRow('Services', (_billPreview!['services'] as List?)?.join(', ') ?? ''),
                  const Divider(height: 20),
                  _CalcRow('Labour',  '₹${(_billPreview!['labour'] as num?)?.toStringAsFixed(2) ?? '0.00'}', bold: false),
                  _CalcRow('Parts',   '₹${(_billPreview!['parts']  as num?)?.toStringAsFixed(2) ?? '0.00'}', bold: false),
                  _CalcRow('GST 18%', '₹${(_billPreview!['gst']    as num?)?.toStringAsFixed(2) ?? '0.00'}', bold: false),
                  if ((_billPreview!['discount'] as num?) != null && (_billPreview!['discount'] as num) > 0)
                    _CalcRow('Discount', '−₹${(_billPreview!['discount'] as num).toStringAsFixed(2)}', bold: false),
                  const Divider(height: 16),
                  _CalcRow(
                    'Total',
                    '₹${(_billPreview!['total'] is num) ? (_billPreview!['total'] as num).toStringAsFixed(2) : _billPreview!['total']}',
                    bold: true,
                  ),
                  // ── Collect payment ───────────────────────────────────────
                  if (_billPreview!['payment_status'] != 'paid') ...[
                    const SizedBox(height: 20),
                    const Text('Collect Payment',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A2332))),
                    const SizedBox(height: 10),
                    _PaymentMethodPicker(
                      selected: _selectedPaymentMethod,
                      onSelect: (m) => setState(() => _selectedPaymentMethod = m),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isMarkingPaid ? null : _markAsPaid,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF27AE60),
                          foregroundColor: Colors.white,
                        ),
                        icon: _isMarkingPaid
                            ? const SizedBox(height: 18, width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_outline_rounded, size: 18),
                        label: Text(_isMarkingPaid ? 'Recording…' : 'Mark as Paid'),
                      ),
                    ),
                  ],
                  // ── Mark as Done ────────────────────────────────────────
                  if (_jobStatus == 'completed') ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0x1A27AE60),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF27AE60)),
                        const SizedBox(width: 8),
                        const Text('Job marked as done — customer notified',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF27AE60))),
                      ]),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isMarkingDone ? null : _markAsDone,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D3A4A),
                          foregroundColor: Colors.white,
                        ),
                        icon: _isMarkingDone
                            ? const SizedBox(height: 18, width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.task_alt_rounded, size: 18),
                        label: Text(_isMarkingDone ? 'Marking…' : 'Mark as Done'),
                      ),
                    ),
                  ],
                  // ── WhatsApp share ────────────────────────────────────────
                  if (_customerPhone != null && _customerPhone!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _shareBill,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Send Bill via WhatsApp'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Small helpers ──────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A2332)));
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Color(0xFF7A869A), fontSize: 13)),
      Flexible(child: Text(value,
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A2332)))),
    ]),
  );
}

class _CalcRow extends StatelessWidget {
  const _CalcRow(this.label, this.value, {required this.bold});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: const Color(0xFF4A5568))),
      Text(value, style: TextStyle(fontSize: bold ? 16 : 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: const Color(0xFF1A2332))),
    ],
  );
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.ctrl, required this.label, required this.onChanged});
  final TextEditingController ctrl;
  final String label;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, prefixText: '₹ '),
    onChanged: onChanged,
  );
}

class _PaymentMethodPicker extends StatelessWidget {
  const _PaymentMethodPicker({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  static const _methods = [
    ('cash',        'Cash',        Icons.payments_outlined),
    ('upi',         'UPI',         Icons.phone_android_outlined),
    ('card',        'Card',        Icons.credit_card_outlined),
    ('net_banking', 'Net Banking', Icons.account_balance_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _methods.map((m) {
        final sel = selected == m.$1;
        return GestureDetector(
          onTap: () => onSelect(m.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? const Color(0xFF2D3A4A) : const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(m.$3, size: 15, color: sel ? Colors.white : const Color(0xFF4A5568)),
              const SizedBox(width: 6),
              Text(m.$2,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  color: sel ? Colors.white : const Color(0xFF4A5568),
                )),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2F2),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFFCDD2)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, size: 16, color: Color(0xFFE53935)),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFFE53935)))),
    ]),
  );
}
