import 'package:flutter/material.dart';

import 'api_service.dart';

class QueueBoardScreen extends StatefulWidget {
  const QueueBoardScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<QueueBoardScreen> createState() => _QueueBoardScreenState();
}

class _QueueBoardScreenState extends State<QueueBoardScreen> {
  final List<String> _filters = ['All', 'Queue', 'In Progress', 'Completed'];
  String _selectedFilter = 'All';
  List<dynamic> _todayJobs = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _updatingJobId;

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
    if (filter == 'All') return true;
    final status = _jobStatusValue(job).toLowerCase();
    if (filter == 'Queue') {
      return status.contains('queue') ||
          status.contains('pending') ||
          status.contains('waiting');
    }
    if (filter == 'In Progress') {
      return status.contains('progress') ||
          status.contains('ongoing') ||
          status.contains('in_progress');
    }
    if (filter == 'Completed') {
      return status.contains('complete') || status.contains('done');
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

  List<dynamic> get _filteredJobs => _todayJobs
      .where((job) => _jobMatchesFilter(job, _selectedFilter))
      .toList();

  Widget _buildFilterChips() {
    return SingleChildScrollView(
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
            Text(
              _jobVehicle(job),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _jobCustomer(job),
              style: const TextStyle(fontSize: 14, color: Colors.black87),
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredJobs;
    return Scaffold(
      appBar: AppBar(title: const Text('Queue Board')),
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFilterChips(),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
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
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            _buildJobCard(filtered[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
