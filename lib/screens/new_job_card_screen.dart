import 'package:flutter/material.dart';

import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder  = Color(0xFFE8EAED);

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
  'Wheel Alignment':  Icons.tune,
  'Wheel Balancing':  Icons.rotate_right,
  'Tyre Change':      Icons.tire_repair,
  'Water Wash':       Icons.water_drop_outlined,
  'Full Service':     Icons.build_outlined,
  'Car Wash':         Icons.local_car_wash_outlined,
  'Other':            Icons.miscellaneous_services_outlined,
};

class NewJobCardScreen extends StatefulWidget {
  const NewJobCardScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<NewJobCardScreen> createState() => _NewJobCardScreenState();
}

class _NewJobCardScreenState extends State<NewJobCardScreen> {
  final _formKey              = GlobalKey<FormState>();
  final _vehicleCtrl          = TextEditingController();
  final _customerNameCtrl     = TextEditingController();
  final _phoneCtrl            = TextEditingController();
  final _notesCtrl            = TextEditingController();

  String? _selectedService;
  String  _source       = 'Walk-in';
  bool    _isSubmitting = false;
  String? _serviceError;

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    _customerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedService == null) {
      setState(() => _serviceError = 'Please select a service.');
      return;
    }

    setState(() { _serviceError = null; _isSubmitting = true; });

    try {
      await widget.apiService.createJob(
        _vehicleCtrl.text.trim(),
        _customerNameCtrl.text.trim(),
        _phoneCtrl.text.trim(),
        [_selectedService!],
        _notesCtrl.text.trim(),
        _source,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is ApiException ? error.toString() : 'Unable to submit job.'),
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('New Job Card'),
        backgroundColor: _colorPrimary,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(children: [
                _label('Vehicle Registration *'),
                const SizedBox(height: 8),
                _field(_vehicleCtrl, 'e.g. MH12AB1234',
                    icon: Icons.directions_car_outlined,
                    caps: TextCapitalization.characters,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              ]),
              const SizedBox(height: 12),

              _card(children: [
                _label('Customer Details'),
                const SizedBox(height: 12),
                _field(_customerNameCtrl, 'Customer Name',
                    icon: Icons.person_outline,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                _field(_phoneCtrl, 'Phone Number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              ]),
              const SizedBox(height: 12),

              _card(children: [
                _label('Service Type *'),
                const SizedBox(height: 12),
                _ServiceGrid(
                  selected: _selectedService,
                  onSelect: (s) => setState(() { _selectedService = s; _serviceError = null; }),
                ),
                if (_serviceError != null) ...[
                  const SizedBox(height: 8),
                  Text(_serviceError!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFE53935))),
                ],
              ]),
              const SizedBox(height: 12),

              _card(children: [
                _label('Source'),
                const SizedBox(height: 10),
                Row(children: [
                  for (final src in ['Walk-in', 'WhatsApp'])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: src == 'Walk-in' ? 8 : 0),
                        child: GestureDetector(
                          onTap: () => setState(() => _source = src),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _source == src ? _colorPrimary : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _source == src ? _colorPrimary : _colorBorder),
                            ),
                            child: Text(src,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: _source == src ? Colors.white : _colorSubtext,
                                )),
                          ),
                        ),
                      ),
                    ),
                ]),
              ]),
              const SizedBox(height: 12),

              _card(children: [
                _label('Notes (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14, color: _colorHeading),
                  decoration: InputDecoration(
                    hintText: 'Any additional notes…',
                    hintStyle: const TextStyle(fontSize: 13, color: _colorSubtext),
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
                      borderSide: const BorderSide(color: _colorPrimary, width: 1.5),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _colorPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(height: 22, width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Create Job Card',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading));

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
        prefixIcon: icon != null ? Icon(icon, size: 20, color: _colorSubtext) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _colorBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _colorBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _colorPrimary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE53935))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5)),
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
                Icon(_serviceIcons[s] ?? Icons.miscellaneous_services_outlined,
                    size: 22, color: sel ? Colors.white : _colorSubtext),
                const SizedBox(height: 6),
                Text(s,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : _colorSubtext,
                    )),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
