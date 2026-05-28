import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garage_manager/services/api_service.dart';

class QueueBoardScreen extends StatefulWidget {
  const QueueBoardScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<QueueBoardScreen> createState() => _QueueBoardScreenState();
}

class _QueueBoardScreenState extends State<QueueBoardScreen> {
  final List<String> _filters = ['All', 'In Progress', 'Completed'];
  String _selectedFilter = 'All';
  List<dynamic> _todayJobs = [];
  final List<dynamic> _createdJobs = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _updatingJobId;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiService.getTodayJobs();
      if (response is List) {
        _todayJobs = response;
      } else if (response is Map<String, dynamic> && response['jobs'] is List) {
        _todayJobs = response['jobs'] as List<dynamic>;
      } else {
        _todayJobs = [];
      }
      _attachCreatedJobs();
    } catch (error) {
      _errorMessage = error is ApiException
          ? error.toString()
          : 'Failed to load jobs.';
      _todayJobs = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _jobMatchesFilter(dynamic job, String filter) {
    final status = _jobStatusValue(job).toLowerCase();
    if (filter == 'All') {
      return !status.contains('pending');
    }
    if (filter == 'In Progress') {
      return status.contains('progress') || status.contains('in_progress');
    }
    if (filter == 'Completed') {
      return status.contains('complete') || status.contains('delivered');
    }
    return false;
  }

  String _jobStatusValue(dynamic job) {
    if (job is Map<String, dynamic>) {
      return job['status']?.toString() ?? 'Unknown';
    }
    return 'Unknown';
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('complete') || value.contains('done')) {
      return Colors.green;
    }
    if (value.contains('progress') ||
        value.contains('ongoing') ||
        value.contains('in_progress')) {
      return Colors.blue;
    }
    return Colors.amber;
  }

  Future<void> _updateJobStatus(dynamic job) async {
    final id = _jobId(job);
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update status: missing job ID.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _updatingJobId = id;
    });

    try {
      await widget.apiService.updateJobStatus(id);
      await _loadJobs();
    } catch (error) {
      if (mounted) {
        final message = error is ApiException
            ? error.toString()
            : 'Failed to update status.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingJobId = null;
        });
      }
    }
  }

  String? _jobId(dynamic job) {
    if (job is Map<String, dynamic>) {
      return job['id']?.toString() ?? job['jobId']?.toString();
    }
    return null;
  }

  String _jobVehicle(dynamic job) {
    if (job is Map<String, dynamic>) {
      return job['vehicleReg']?.toString() ??
          job['vehicle']?.toString() ??
          'Unknown vehicle';
    }
    return 'Unknown vehicle';
  }

  String _jobCustomer(dynamic job) {
    if (job is Map<String, dynamic>) {
      return job['customerName']?.toString() ??
          job['customer']?.toString() ??
          'Unknown customer';
    }
    return 'Unknown customer';
  }

  List<String> _jobServices(dynamic job) {
    if (job is Map<String, dynamic>) {
      final services = job['services'];
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
    }
    return <String>[];
  }

  void _attachCreatedJobs() {
    if (_createdJobs.isEmpty) return;
    final existingIds = _todayJobs.map(_jobId).whereType<String>().toSet();

    final newJobs = _createdJobs.where((job) {
      final id = _jobId(job);
      return id == null || !existingIds.contains(id);
    }).toList();

    if (newJobs.isNotEmpty) {
      _todayJobs = [..._todayJobs, ...newJobs];
    }
  }

  Future<void> _createJob(
    String vehicleReg,
    String customerName,
    String phone,
    String servicesInput,
    String notes,
    String source,
  ) async {
    final services = servicesInput
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    final localJob = <String, dynamic>{
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
      'vehicleReg': vehicleReg,
      'customerName': customerName,
      'customerPhone': phone,
      'services': services,
      'notes': notes,
      'source': source,
      'status': 'pending',
    };

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiService.createJob(
        vehicleReg,
        customerName,
        phone,
        services,
        notes,
        source,
      );

      if (response is Map<String, dynamic>) {
        final createdJob = {
          ...localJob,
          ...response,
          'status': response['status']?.toString().isNotEmpty == true
              ? response['status']
              : 'pending',
        };
        _createdJobs.add(createdJob);
        _todayJobs.add(createdJob);
      } else {
        _createdJobs.add(localJob);
        _todayJobs.add(localJob);
      }
    } catch (error) {
      _createdJobs.add(localJob);
      _todayJobs.add(localJob);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to create job on server. Added locally to queue.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showAddJobDialog() async {
    final vehicleController = TextEditingController();
    final customerController = TextEditingController();
    final phoneController = TextEditingController();
    final servicesController = TextEditingController();
    final notesController = TextEditingController();
    String source = 'Walk-in';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Job'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: customerController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vehicleController,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Registration',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: servicesController,
                decoration: const InputDecoration(
                  labelText: 'Services (comma separated)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: source,
                decoration: const InputDecoration(
                  labelText: 'Source',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'Walk-in', child: Text('Walk-in')),
                  DropdownMenuItem(value: 'WhatsApp', child: Text('WhatsApp')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    source = value;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final vehicle = vehicleController.text.trim();
              final customer = customerController.text.trim();
              final phone = phoneController.text.trim();
              final services = servicesController.text.trim();

              if (customer.isEmpty || phone.isEmpty || vehicle.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Customer, phone, and vehicle are required.'),
                  ),
                );
                return;
              }

              Navigator.of(context).pop();
              _createJob(
                vehicle,
                customer,
                phone,
                services,
                notesController.text.trim(),
                source,
              );
            },
            child: const Text('Create Job'),
          ),
        ],
      ),
    );
  }

  List<dynamic> get _pendingJobs => _todayJobs
      .where((job) => _jobStatusValue(job).toLowerCase() == 'pending')
      .toList();

  String _customerPhone(dynamic job) {
    if (job is Map<String, dynamic>) {
      return job['customerPhone']?.toString() ??
          job['phone']?.toString() ??
          job['contact']?.toString() ??
          '';
    }
    return '';
  }

  String _jobSource(dynamic job) {
    if (job is Map<String, dynamic>) {
      final source = job['source']?.toString().toLowerCase() ?? '';
      if (source.contains('whatsapp') || source.contains('wa')) {
        return 'WhatsApp';
      }
    }
    return 'Walk-in';
  }

  Future<void> _acceptNewJob(dynamic job) async {
    final id = _jobId(job);
    if (id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to accept job: missing job ID.'),
          ),
        );
      }
      return;
    }

    final phone = _customerPhone(job);
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to accept job: missing customer phone.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _updatingJobId = id;
    });

    try {
      await widget.apiService.updateJobStatus(id);

      final customerName = _jobCustomer(job);
      final vehicleReg = _jobVehicle(job);
      final message = Uri.encodeComponent(
        'Hello $customerName, your vehicle $vehicleReg has been accepted at our garage. We will begin work shortly. Thank you!',
      );
      final whatsappUri = Uri.parse('https://wa.me/$phone?text=$message');

      if (!await launchUrl(whatsappUri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open WhatsApp.');
      }
    } catch (error) {
      if (mounted) {
        final message = error is ApiException
            ? error.toString()
            : 'Failed to accept job. ${error.toString()}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _updatingJobId = null;
        });
      }
      await _loadJobs();
    }
  }

  void _cancelJob(dynamic job) {
    setState(() {
      _todayJobs.remove(job);
      _createdJobs.removeWhere((created) {
        final createdId = _jobId(created);
        final jobId = _jobId(job);
        return createdId != null && jobId != null && createdId == jobId;
      });
    });

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Job canceled.')));
    }
  }

  Widget _buildNewJobCard(dynamic job) {
    final services = _jobServices(job);
    final jobId = _jobId(job);
    final isAccepting = jobId != null && _updatingJobId == jobId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _jobVehicle(job),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'cancel') {
                      _cancelJob(job);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _jobCustomer(job),
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
                Chip(
                  label: Text(_jobSource(job)),
                  backgroundColor: Colors.grey.shade100,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _customerPhone(job),
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: services.map((service) {
                return Chip(
                  label: Text(service),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: isAccepting ? null : () => _acceptNewJob(job),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isAccepting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Accept'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> get _filteredJobs => _todayJobs
      .where((job) => _jobMatchesFilter(job, _selectedFilter))
      .toList();

  Widget _buildFilterChips() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _filters.map((filter) {
              final selected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobCard(dynamic job) {
    final status = _jobStatusValue(job);
    final services = _jobServices(job);
    final jobId = _jobId(job);
    final isUpdating = jobId != null && _updatingJobId == jobId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _jobVehicle(job),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'cancel') {
                      _cancelJob(job);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _jobCustomer(job),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              _customerPhone(job),
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: services.map((service) {
                return Chip(
                  label: Text(service),
                  backgroundColor: Colors.grey.shade100,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: isUpdating ? null : () => _updateJobStatus(job),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUpdating)
                            const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          else
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _statusColor(status),
                                shape: BoxShape.circle,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            status,
                            style: TextStyle(
                              color: _statusColor(status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (jobId != null)
                  Text(
                    'ID: $jobId',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueContent() {
    final filtered = _filteredJobs;
    final pendingJobs = _pendingJobs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildFilterChips(),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadJobs,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                if (pendingJobs.isNotEmpty) ...[
                  const Text(
                    'New Jobs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...pendingJobs.map(_buildNewJobCard),
                  const SizedBox(height: 20),
                ],
                if (_isLoading) ...[
                  const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ] else if (filtered.isEmpty) ...[
                  SizedBox(
                    height: 300,
                    child: Center(
                      child: Text(
                        _todayJobs.isEmpty
                            ? 'No jobs available right now.'
                            : 'No jobs match the "$_selectedFilter" filter.',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ] else ...[
                  ...filtered.map(_buildJobCard),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScreenBottomBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.view_list_rounded),
          label: 'Queue',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_rounded),
          label: 'Dashboard',
        ),
      ],
    );
  }

  Widget _buildDashboardContent() {
    final totalJobs = _todayJobs.length;
    final queueJobs = _pendingJobs.length;
    final inProgressJobs = _todayJobs
        .where((job) => _jobMatchesFilter(job, 'In Progress'))
        .length;
    final completedJobs = _todayJobs
        .where((job) => _jobMatchesFilter(job, 'Completed'))
        .length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildStatsCard('Total Jobs', '$totalJobs', Colors.blueGrey),
              const SizedBox(width: 12),
              _buildStatsCard('In Progress', '$inProgressJobs', Colors.blue),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatsCard('Queued', '$queueJobs', Colors.amber.shade700),
              const SizedBox(width: 12),
              _buildStatsCard('Completed', '$completedJobs', Colors.green),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap the Queue tab to manage jobs and update job status quickly.',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        const Chip(label: Text('View Today')),
                        ActionChip(
                          label: const Text('Add Job'),
                          onPressed: _showAddJobDialog,
                        ),
                        const Chip(label: Text('Customer History')),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showAddJobDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Job'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Queue Board', 'Dashboard'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_selectedIndex])),
      body: _selectedIndex == 0
          ? _buildQueueContent()
          : _buildDashboardContent(),
      bottomNavigationBar: _buildScreenBottomBar(),
    );
  }
}
