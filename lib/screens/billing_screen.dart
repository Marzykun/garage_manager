import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garage_manager/services/api_service.dart';

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
  final Map<String, double> _servicePrices = {
    'Wash': 200.0,
    'Tyre Change': 500.0,
    'Alignment': 350.0,
    'Balancing': 300.0,
  };

  bool _isLoading = true;
  bool _isGenerating = false;
  Map<String, dynamic> _jobData = {};
  double _extraCharges = 0.0;
  final TextEditingController _extraChargeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  Map<String, dynamic>? _billPreview;
  String? _customerPhone;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadJobDetails();
  }

  @override
  void dispose() {
    _extraChargeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadJobDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiService.getJob(widget.jobId);
      if (response is Map<String, dynamic>) {
        setState(() {
          _jobData = response;
          _customerPhone =
              response['phone']?.toString() ??
              response['customerPhone']?.toString();
          _notesController.text = response['notes']?.toString() ?? '';
        });
      } else {
        setState(() {
          _jobData = {};
          _errorMessage = 'Unable to load job details.';
        });
      }
    } catch (error) {
      setState(() {
        _jobData = {};
        _errorMessage = error is ApiException
            ? error.toString()
            : 'Unable to load job details.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<String> get _selectedServices {
    final services = _jobData['services'];
    if (services is List) {
      return services.map((item) => item.toString()).toList();
    }
    if (services is String) {
      return services
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  String get _vehicleNumber =>
      _jobData['vehicleReg']?.toString() ??
      _jobData['vehicle']?.toString() ??
      'Unknown';
  String get _customerName =>
      _jobData['customerName']?.toString() ??
      _jobData['customer']?.toString() ??
      'Unknown';

  double get _serviceTotal {
    return _selectedServices.fold(0.0, (sum, service) {
      return sum + (_servicePrices[service] ?? 0.0);
    });
  }

  double get _totalAmount => _serviceTotal + _extraCharges;

  Future<void> _generateBill() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    if (_extraChargeController.text.isNotEmpty) {
      _extraCharges =
          double.tryParse(_extraChargeController.text.trim()) ?? 0.0;
    } else {
      _extraCharges = 0.0;
    }

    try {
      final response = await widget.apiService.generateBill(widget.jobId);
      final preview = <String, dynamic>{
        'customerName': _customerName,
        'vehicleReg': _vehicleNumber,
        'services': _selectedServices,
        'total': _totalAmount,
        'date': DateTime.now().toIso8601String(),
        'phone': _customerPhone,
      };

      if (response is Map<String, dynamic>) {
        preview['billId'] = response['billId'] ?? response['id'];
        preview['date'] = response['date']?.toString() ?? preview['date'];
        preview['total'] =
            response['total'] ?? response['amount'] ?? _totalAmount;
      }

      setState(() {
        _billPreview = preview;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error is ApiException
            ? error.toString()
            : 'Unable to generate bill.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _shareBill() async {
    if (_billPreview == null ||
        _customerPhone == null ||
        _customerPhone!.isEmpty) {
      return;
    }

    final message = StringBuffer()
      ..writeln('Garage Manager Bill')
      ..writeln('Customer: ${_billPreview!['customerName']}')
      ..writeln('Vehicle: ${_billPreview!['vehicleReg']}')
      ..writeln('Services:')
      ..writeln(_selectedServices.map((s) => '- $s').join('\n'))
      ..writeln('Total: ₹${_billPreview!['total'].toString()}')
      ..writeln('Date: ${_billPreview!['date']}');

    final encoded = Uri.encodeComponent(message.toString());
    final uri = Uri.parse('https://wa.me/${_customerPhone!}?text=$encoded');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text(
                    'Job details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTile('Vehicle', _vehicleNumber),
                  _buildInfoTile('Customer', _customerName),
                  const SizedBox(height: 16),
                  const Text(
                    'Selected services',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ..._selectedServices.map(
                    (service) => _buildServiceTile(
                      service,
                      _servicePrices[service] ?? 0.0,
                    ),
                  ),
                  const Divider(height: 32),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.note),
                      border: OutlineInputBorder(),
                      hintText: 'Add any extra notes for the bill',
                    ),
                    maxLines: 3,
                    textInputAction: TextInputAction.newline,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _extraChargeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Extra Charges',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                      hintText: 'Add any extra charges',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _extraCharges =
                            double.tryParse(
                              _extraChargeController.text.trim(),
                            ) ??
                            0.0;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isGenerating ? null : _generateBill,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isGenerating
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
                        : const Text('Generate Bill'),
                  ),
                  if (_billPreview != null) ...[
                    const SizedBox(height: 32),
                    const Text(
                      'Bill preview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPreviewRow(
                              'Customer',
                              _billPreview!['customerName']?.toString() ?? '',
                            ),
                            _buildPreviewRow(
                              'Vehicle',
                              _billPreview!['vehicleReg']?.toString() ?? '',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Services',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            ..._selectedServices.map(
                              (service) => Text('• $service'),
                            ),
                            const SizedBox(height: 12),
                            _buildPreviewRow(
                              'Total',
                              '₹${_formatAmount(_billPreview!['total'])}',
                            ),
                            _buildPreviewRow(
                              'Date',
                              _billPreview!['date']?.toString() ?? '',
                            ),
                            if (_customerPhone != null &&
                                _customerPhone!.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _shareBill,
                                icon: const Icon(Icons.share),
                                label: const Text('Share via WhatsApp'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildServiceTile(String service, double price) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(service),
      trailing: Text('₹${price.toStringAsFixed(2)}'),
    );
  }

  String _formatAmount(dynamic amount) {
    if (amount is num) {
      return amount.toDouble().toStringAsFixed(2);
    }
    if (amount is String) {
      final parsed = double.tryParse(amount);
      if (parsed != null) {
        return parsed.toStringAsFixed(2);
      }
    }
    return _totalAmount.toStringAsFixed(2);
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
