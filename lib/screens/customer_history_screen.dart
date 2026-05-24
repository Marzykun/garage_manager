import 'dart:async';

import 'package:flutter/material.dart';

import 'package:garage_manager/services/api_service.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<dynamic> _customers = [];
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _searchCustomers(_searchController.text.trim());
    });
  }

  Future<void> _searchCustomers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _customers = [];
        _errorMessage = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiService.searchCustomers(query);
      if (response is List) {
        setState(() {
          _customers = response;
        });
      } else if (response is Map<String, dynamic>) {
        if (response['customers'] is List) {
          setState(() {
            _customers = response['customers'] as List<dynamic>;
          });
        } else {
          setState(() {
            _customers = [];
          });
        }
      } else {
        setState(() {
          _customers = [];
        });
      }
    } catch (error) {
      setState(() {
        _customers = [];
        _errorMessage = error is ApiException
            ? error.toString()
            : 'Unable to search customers.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  String _customerName(dynamic item) {
    if (item is Map<String, dynamic>) {
      return item['name']?.toString() ??
          item['customerName']?.toString() ??
          'Unknown customer';
    }
    return 'Unknown customer';
  }

  String _customerPhone(dynamic item) {
    if (item is Map<String, dynamic>) {
      return item['phone']?.toString() ??
          item['customerPhone']?.toString() ??
          'Unknown phone';
    }
    return 'Unknown phone';
  }

  String _customerVehicle(dynamic item) {
    if (item is Map<String, dynamic>) {
      return item['vehicleReg']?.toString() ??
          item['vehicle']?.toString() ??
          'Unknown vehicle';
    }
    return 'Unknown vehicle';
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    final emptyState = query.isNotEmpty && !_isSearching && _customers.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer History')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search customers',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged();
                          },
                        )
                      : null,
                ),
                onChanged: (_) => _onSearchChanged(),
                textInputAction: TextInputAction.search,
              ),
              const SizedBox(height: 16),
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else if (emptyState)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No customers found. Try a different name, phone number, or vehicle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _customers.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = _customers[index];
                      return ListTile(
                        title: Text(_customerName(customer)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_customerPhone(customer)),
                            Text(_customerVehicle(customer)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          final phone = _customerPhone(customer);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CustomerHistoryDetailScreen(
                                apiService: widget.apiService,
                                customerName: _customerName(customer),
                                phone: phone,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerHistoryDetailScreen extends StatefulWidget {
  const CustomerHistoryDetailScreen({
    super.key,
    required this.apiService,
    required this.customerName,
    required this.phone,
  });

  final ApiService apiService;
  final String customerName;
  final String phone;

  @override
  State<CustomerHistoryDetailScreen> createState() =>
      _CustomerHistoryDetailScreenState();
}

class _CustomerHistoryDetailScreenState
    extends State<CustomerHistoryDetailScreen> {
  late Future<List<dynamic>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<dynamic>> _loadHistory() async {
    final response = await widget.apiService.getCustomerHistory(widget.phone);
    if (response is List) {
      return response;
    }
    if (response is Map<String, dynamic>) {
      if (response['history'] is List) {
        return response['history'] as List<dynamic>;
      }
      if (response['visits'] is List) {
        return response['visits'] as List<dynamic>;
      }
    }
    return [];
  }

  String _formatDate(dynamic record) {
    if (record is Map<String, dynamic>) {
      final raw = record['date'] ?? record['visitDate'] ?? record['createdAt'];
      if (raw is String && raw.isNotEmpty) {
        return raw;
      }
      if (raw is DateTime) {
        return '${raw.year}-${raw.month.toString().padLeft(2, '0')}-${raw.day.toString().padLeft(2, '0')}';
      }
    }
    return 'Unknown date';
  }

  String _formatServices(dynamic record) {
    if (record is Map<String, dynamic>) {
      final services = record['services'];
      if (services is List) {
        return services.map((value) => value.toString()).join(', ');
      }
      if (services is String) {
        return services;
      }
    }
    return 'No services available';
  }

  String _formatAmount(dynamic record) {
    if (record is Map<String, dynamic>) {
      final amount =
          record['amount'] ?? record['billedAmount'] ?? record['total'];
      if (amount != null) {
        return amount.toString();
      }
    }
    return 'N/A';
  }

  String _formatStatus(dynamic record) {
    if (record is Map<String, dynamic>) {
      return record['status']?.toString() ?? 'Unknown';
    }
    return 'Unknown';
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('complete') || value.contains('done')) {
      return Colors.green;
    }
    if (value.contains('progress') || value.contains('ongoing')) {
      return Colors.blue;
    }
    if (value.contains('queue') || value.contains('pending')) {
      return Colors.amber;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.customerName)),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final history = snapshot.data ?? [];
          if (history.isEmpty) {
            return const Center(
              child: Text(
                'No past visits found for this customer.',
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final record = history[index];
              final status = _formatStatus(record);

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDate(record),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Chip(
                            label: Text(status),
                            backgroundColor: _statusColor(
                              status,
                            ).withOpacity(0.18),
                            labelStyle: TextStyle(color: _statusColor(status)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Services: ${_formatServices(record)}'),
                      const SizedBox(height: 8),
                      Text('Amount billed: ${_formatAmount(record)}'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
