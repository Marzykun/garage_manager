import 'package:flutter/material.dart';

import 'api_service.dart';

class NewJobCardScreen extends StatefulWidget {
  const NewJobCardScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<NewJobCardScreen> createState() => _NewJobCardScreenState();
}

class _NewJobCardScreenState extends State<NewJobCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final List<String> _serviceOptions = [
    'Wash',
    'Tyre Change',
    'Alignment',
    'Balancing',
  ];
  late List<bool> _selectedServices;
  String _source = 'Walk-in';
  String? _servicesError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedServices = List<bool>.filled(_serviceOptions.length, false);
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _customerNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final selectedServices = <String>[];
    for (var i = 0; i < _serviceOptions.length; i++) {
      if (_selectedServices[i]) {
        selectedServices.add(_serviceOptions[i]);
      }
    }

    if (selectedServices.isEmpty) {
      setState(() {
        _servicesError = 'Please select at least one service.';
      });
      return;
    }

    setState(() {
      _servicesError = null;
      _isSubmitting = true;
    });

    try {
      await widget.apiService.createCustomer(
        _customerNameController.text.trim(),
        _phoneController.text.trim(),
        _vehicleController.text.trim(),
      );

      await widget.apiService.createJob(
        _vehicleController.text.trim(),
        _customerNameController.text.trim(),
        _phoneController.text.trim(),
        selectedServices,
        _notesController.text.trim(),
        _source,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      final message = error is ApiException
          ? error.toString()
          : 'Unable to submit job. ${error.toString()}';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildServiceCheckbox(int index) {
    return CheckboxListTile(
      title: Text(_serviceOptions[index]),
      value: _selectedServices[index],
      onChanged: (value) {
        setState(() {
          _selectedServices[index] = value ?? false;
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSourceSelector() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            label: const Text('Walk-in'),
            selected: _source == 'Walk-in',
            onSelected: (_) => setState(() => _source = 'Walk-in'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChoiceChip(
            label: const Text('WhatsApp'),
            selected: _source == 'WhatsApp',
            onSelected: (_) => setState(() => _source = 'WhatsApp'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Job Card')),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _vehicleController,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Registration',
                    prefixIcon: Icon(Icons.directions_car),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vehicle registration is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _customerNameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Customer name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Customer Phone',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Phone number is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Services',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...List.generate(_serviceOptions.length, _buildServiceCheckbox),
                if (_servicesError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      _servicesError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Source',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildSourceSelector(),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.note),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Submit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
