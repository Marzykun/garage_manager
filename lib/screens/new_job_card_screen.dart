import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:garage_manager/models/vehicle_types.dart';
import 'package:garage_manager/screens/customer_history_screen.dart';
import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder = Color(0xFFE8EAED);

const _serviceOptions = [
  'Wheel Alignment',
  'Wheel Balancing',
  'Tyre Change',
  'Water Wash',
  'Full Service',
  'Car Wash',
  'Other',
];

const _serviceIcons = {
  'Wheel Alignment': Icons.tune,
  'Wheel Balancing': Icons.rotate_right,
  'Tyre Change': Icons.tire_repair,
  'Water Wash': Icons.water_drop_outlined,
  'Full Service': Icons.build_outlined,
  'Car Wash': Icons.local_car_wash_outlined,
  'Other': Icons.miscellaneous_services_outlined,
};

/// Creates a job card, or — when [job] is given — edits that job's details
/// (customer name/phone, vehicle, service, notes).
class NewJobCardScreen extends StatefulWidget {
  const NewJobCardScreen({super.key, required this.apiService, this.job});
  final ApiService apiService;
  final Map<String, dynamic>? job;

  @override
  State<NewJobCardScreen> createState() => _NewJobCardScreenState();
}

class _NewJobCardScreenState extends State<NewJobCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  String? _vehicleType;

  String? _selectedService;
  String _source = 'Walk-in';
  bool _isSubmitting = false;
  String? _serviceError;

  bool get _isEdit => widget.job != null;

  // ── Returning-vehicle lookup (New Job only) ──
  Timer? _lookupDebounce;
  Map<String, dynamic>? _returning; // lookup result for the typed plate
  bool _lookingUp = false;
  String _lastLookedUp = '';
  // Values we filled in automatically — replaced if the plate changes again,
  // but anything the user typed themselves is never overwritten.
  final Map<TextEditingController, String> _autoFilled = {};
  String? _autoType;

  String _plateKey(String v) =>
      v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  void _onPlateChanged() {
    if (_isEdit) return;
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 500), _lookupPlate);
  }

  Future<void> _lookupPlate() async {
    final key = _plateKey(_vehicleCtrl.text);
    if (key == _lastLookedUp) return;
    _lastLookedUp = key;
    if (key.length < 4) {
      if (_returning != null) {
        setState(() {
          _returning = null;
          _clearAutoFilled();
        });
      }
      return;
    }
    setState(() => _lookingUp = true);
    try {
      final data = await widget.apiService.lookupVehicle(key);
      // Ignore stale results if the plate was edited while we waited
      if (!mounted || _plateKey(_vehicleCtrl.text) != key) return;
      setState(() {
        _clearAutoFilled();
        _returning = data;
        if (data != null) _applyReturning(data);
      });
    } catch (_) {
      // Lookup is a convenience — on any error just leave the form as typed
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _fill(TextEditingController c, dynamic value) {
    final v = value?.toString().trim() ?? '';
    if (v.isEmpty || c.text.trim().isNotEmpty) return;
    c.text = v;
    _autoFilled[c] = v;
  }

  void _applyReturning(Map<String, dynamic> d) {
    final cust = (d['customer'] as Map?) ?? {};
    final veh = (d['vehicle'] as Map?) ?? {};
    _fill(_customerNameCtrl, cust['name']);
    _fill(_phoneCtrl, cust['phone']);
    _fill(_brandCtrl, veh['brand']);
    _fill(_modelCtrl, veh['model']);
    if (_vehicleType == null) {
      _autoType = vehicleTypeFor(veh['vehicle_type']?.toString())?.value;
      _vehicleType = _autoType;
    }
  }

  void _clearAutoFilled() {
    _autoFilled.forEach((c, v) {
      if (c.text == v) c.clear();
    });
    _autoFilled.clear();
    if (_autoType != null && _vehicleType == _autoType) _vehicleType = null;
    _autoType = null;
  }

  /// Odometer from the km box — commas/spaces ignored, blank = not recorded.
  int? get _km => int.tryParse(_kmCtrl.text.replaceAll(RegExp(r'[,\s]'), ''));

  @override
  void initState() {
    super.initState();
    _vehicleCtrl.addListener(_onPlateChanged);
    final j = widget.job;
    if (j != null) {
      _vehicleCtrl.text = j['vehicle_number']?.toString() ?? '';
      _customerNameCtrl.text = j['customer_name']?.toString() ?? '';
      _phoneCtrl.text = j['customer_phone']?.toString() ?? '';
      _notesCtrl.text = j['notes']?.toString() ?? '';
      _brandCtrl.text = j['brand']?.toString() ?? '';
      _modelCtrl.text = j['model']?.toString() ?? '';
      _kmCtrl.text = j['km_reading']?.toString() ?? '';
      _vehicleType = vehicleTypeFor(j['vehicle_type']?.toString())?.value;
      final st = j['service_type']?.toString();
      _selectedService = st == null ? null : serviceLabel(st);
      if (!_serviceOptions.contains(_selectedService)) _selectedService = null;
    }
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _vehicleCtrl.removeListener(_onPlateChanged);
    _vehicleCtrl.dispose();
    _customerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _kmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedService == null) {
      setState(() => _serviceError = 'Please select a service.');
      return;
    }

    setState(() {
      _serviceError = null;
      _isSubmitting = true;
    });

    try {
      if (_isEdit) {
        await widget.apiService.updateJobDetails(
          widget.job!['id'].toString(),
          customerName: _customerNameCtrl.text.trim(),
          customerPhone: _phoneCtrl.text.trim(),
          vehicleNumber: _vehicleCtrl.text.trim(),
          vehicleType: _vehicleType,
          vehicleBrand: _brandCtrl.text.trim(),
          vehicleModel: _modelCtrl.text.trim(),
          kmReading: _km,
          service: _selectedService!,
          notes: _notesCtrl.text.trim(),
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }
      await widget.apiService.createJob(
        _vehicleCtrl.text.trim(),
        _customerNameCtrl.text.trim(),
        _phoneCtrl.text.trim(),
        [_selectedService!],
        _notesCtrl.text.trim(),
        _source,
        vehicleType: _vehicleType,
        vehicleBrand: _brandCtrl.text.trim(),
        vehicleModel: _modelCtrl.text.trim(),
        kmReading: _km,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException ? error.toString() : 'Unable to submit job.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Job' : 'New Job Card'),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
        // The app theme sets a dark title style; override it on this dark bar
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                children: [
                  _label('Vehicle Registration *'),
                  const SizedBox(height: 8),
                  _field(
                    _vehicleCtrl,
                    'e.g. MH12AB1234',
                    icon: Icons.directions_car_outlined,
                    caps: TextCapitalization.characters,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  if (!_isEdit && (_lookingUp || _returning != null)) ...[
                    const SizedBox(height: 10),
                    _lookingUp && _returning == null
                        ? const Text(
                            'Checking for previous visits…',
                            style: TextStyle(
                              fontSize: 12,
                              color: _colorSubtext,
                            ),
                          )
                        : _ReturningPanel(
                            data: _returning!,
                            onTap: () {
                              final cust = (_returning!['customer'] as Map?)
                                  ?.cast<String, dynamic>();
                              if (cust == null || cust['id'] == null) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CustomerDetailScreen(
                                    apiService: widget.apiService,
                                    customer: cust,
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                  const SizedBox(height: 14),
                  _label('Vehicle Type'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in kVehicleTypes)
                        ChoiceChip(
                          avatar: Icon(
                            t.icon,
                            size: 18,
                            color: _vehicleType == t.value
                                ? Colors.white
                                : _colorSubtext,
                          ),
                          label: Text(t.label),
                          selected: _vehicleType == t.value,
                          showCheckmark: false,
                          selectedColor: _colorPrimary,
                          backgroundColor: const Color(0xFFF0F4F8),
                          side: BorderSide(
                            color: _vehicleType == t.value
                                ? _colorPrimary
                                : _colorBorder,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _vehicleType == t.value
                                ? Colors.white
                                : _colorSubtext,
                          ),
                          onSelected: (_) => setState(
                            () => _vehicleType = _vehicleType == t.value
                                ? null
                                : t.value,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          _brandCtrl,
                          'Make (e.g. Maruti)',
                          caps: TextCapitalization.words,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          _modelCtrl,
                          'Model (e.g. Swift)',
                          caps: TextCapitalization.words,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _kmCtrl,
                    'Kilometres run (odometer)',
                    icon: Icons.speed_outlined,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final t = (v ?? '').replaceAll(RegExp(r'[,\s]'), '');
                      if (t.isEmpty) return null;
                      return int.tryParse(t) == null ? 'Numbers only' : null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _card(
                children: [
                  _label('Customer Details'),
                  const SizedBox(height: 12),
                  _field(
                    _customerNameCtrl,
                    'Customer Name',
                    icon: Icons.person_outline,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    _phoneCtrl,
                    'Phone Number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _card(
                children: [
                  _label('Service Type *'),
                  const SizedBox(height: 12),
                  _ServiceGrid(
                    selected: _selectedService,
                    onSelect: (s) => setState(() {
                      _selectedService = s;
                      _serviceError = null;
                    }),
                  ),
                  if (_serviceError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _serviceError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFE53935),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              if (!_isEdit)
                _card(
                  children: [
                    _label('Source'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (final src in ['Walk-in', 'WhatsApp'])
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: src == 'Walk-in' ? 8 : 0,
                              ),
                              child: GestureDetector(
                                onTap: () => setState(() => _source = src),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _source == src
                                        ? _colorPrimary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _source == src
                                          ? _colorPrimary
                                          : _colorBorder,
                                    ),
                                  ),
                                  child: Text(
                                    src,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _source == src
                                          ? Colors.white
                                          : _colorSubtext,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 12),

              _card(
                children: [
                  _label('Notes (optional)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14, color: _colorHeading),
                    decoration: InputDecoration(
                      hintText: 'Any additional notes…',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: _colorSubtext,
                      ),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _colorBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _colorBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: _colorPrimary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEdit ? 'Save Changes' : 'Create Job Card',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _colorBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: _colorHeading,
    ),
  );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    IconData? icon,
    TextInputType? keyboardType,
    TextCapitalization caps = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      textCapitalization: caps,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: _colorSubtext),
        prefixIcon: icon != null
            ? Icon(icon, size: 20, color: _colorSubtext)
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _colorBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _colorBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _colorPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE53935)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
      ),
    );
  }
}

// ── Service selector grid ──────────────────────────────────────────────────────

class _ServiceGrid extends StatelessWidget {
  const _ServiceGrid({required this.selected, required this.onSelect});
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.1,
      children: _serviceOptions.map((s) {
        final sel = selected == s;
        return GestureDetector(
          onTap: () => onSelect(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: sel ? _colorPrimary : const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? _colorPrimary : _colorBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _serviceIcons[s] ?? Icons.miscellaneous_services_outlined,
                  size: 22,
                  color: sel ? Colors.white : _colorSubtext,
                ),
                const SizedBox(height: 6),
                Text(
                  s,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : _colorSubtext,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Returning vehicle summary ─────────────────────────────────────────────────

class _ReturningPanel extends StatelessWidget {
  const _ReturningPanel({required this.data, required this.onTap});
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  static final _date = DateFormat('dd MMM yyyy');
  static final _num = NumberFormat.decimalPattern('en_IN');

  @override
  Widget build(BuildContext context) {
    final cust = (data['customer'] as Map?) ?? {};
    final veh = (data['vehicle'] as Map?) ?? {};
    final jobs = ((data['recent_jobs'] as List?) ?? []).cast<Map>();
    final visits = data['visit_count'] ?? jobs.length;
    final lastKm = int.tryParse(veh['km_run']?.toString() ?? '') ?? 0;

    return Material(
      color: const Color(0xFFEFF6EE),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCDE5C9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Color(0xFF27AE60),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Returning — ${cust['name'] ?? 'customer'} · $visits visit${visits == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _colorHeading,
                      ),
                    ),
                  ),
                  const Text(
                    'History',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF27AE60),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFF27AE60),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                "Details filled in below — check them and add today's km and service.",
                style: TextStyle(fontSize: 11.5, color: _colorSubtext),
              ),
              if (jobs.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Last services',
                  style: TextStyle(fontSize: 12, color: _colorSubtext),
                ),
                for (final j in jobs)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      [
                        serviceLabel(j['service_type']?.toString()),
                        if (DateTime.tryParse(
                              j['created_at']?.toString() ?? '',
                            ) !=
                            null)
                          _date.format(
                            DateTime.parse(
                              j['created_at'].toString(),
                            ).toLocal(),
                          ),
                        if (j['km_reading'] != null)
                          '${_num.format(int.tryParse(j['km_reading'].toString()) ?? 0)} km',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _colorHeading,
                      ),
                    ),
                  ),
              ],
              if (lastKm > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Last recorded odometer: ${_num.format(lastKm)} km',
                  style: const TextStyle(fontSize: 12, color: _colorSubtext),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
