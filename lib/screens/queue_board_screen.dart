import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:garage_manager/services/api_service.dart';
import 'package:garage_manager/screens/billing_screen.dart';
import 'package:garage_manager/screens/customer_history_screen.dart';
import 'package:garage_manager/screens/service_detail_screen.dart';
import 'package:garage_manager/screens/reports_screen.dart';
import 'package:garage_manager/screens/settings_screen.dart';
import 'package:garage_manager/screens/new_job_card_screen.dart';
import 'package:garage_manager/screens/tyre_stock_screen.dart';
import 'package:garage_manager/screens/inventory_screen.dart';

// Pre-computed opacity variants — avoids Color allocation on every build
const _colorPrimary     = Color(0xFF2D3A4A);
const _colorSuccess     = Color(0xFF27AE60);
const _colorInProgress  = Color(0xFF2980B9);
const _colorPending     = Color(0xFFE67E22);
const _colorSurface     = Color(0xFFF4F5F7);
const _colorSuccessBg   = Color(0x1A27AE60);   // success 10%
const _colorProgressBg  = Color(0x1A2980B9);   // progress 10%
const _colorPendingBg   = Color(0x1AE67E22);   // pending 10%
const _colorSuccessWa   = Color(0x1F25D366);   // whatsapp badge bg
const _colorBorder      = Color(0xFFE8EAED);
const _colorSubtext     = Color(0xFF7A869A);
const _colorBodyText    = Color(0xFF4A5568);
const _colorMuted       = Color(0xFFB0B8C4);
const _colorHeading     = Color(0xFF1A2332);
const _colorInputBg     = Color(0xFFF0F2F5);
const _colorWhatsAppText = Color(0xFF1A7A43);
const _colorErrorBg     = Color(0xFFFFF2F2);
const _colorErrorBorder = Color(0xFFFFCDD2);
const _colorErrorText   = Color(0xFFE53935);

Color _statusColor(String status) {
  final v = status.toLowerCase();
  if (v.contains('complete') || v.contains('done')) return _colorSuccess;
  if (v.contains('progress') || v.contains('in_progress')) return _colorInProgress;
  return _colorPending;
}

Color _statusBgColor(String status) {
  final v = status.toLowerCase();
  if (v.contains('complete') || v.contains('done')) return _colorSuccessBg;
  if (v.contains('progress') || v.contains('in_progress')) return _colorProgressBg;
  return _colorPendingBg;
}

String _statusLabel(String status) {
  final v = status.toLowerCase();
  if (v.contains('complete') || v.contains('done')) return 'Completed';
  if (v.contains('progress') || v.contains('in_progress')) return 'In Progress';
  if (v.contains('pending')) return 'Pending';
  return status;
}

// ─── Job data helpers (top-level = no closure allocation) ───────────────────

String jobStatusValue(dynamic job) {
  if (job is Map<String, dynamic>) {
    // Backend returns 'pending' | 'in_progress' | 'completed'
    return job['status']?.toString() ?? 'pending';
  }
  return 'pending';
}

String jobVehicle(dynamic job) {
  if (job is Map<String, dynamic>) {
    return job['vehicle_number']?.toString()
        ?? job['vehicleReg']?.toString()
        ?? job['vehicle']?.toString()
        ?? 'Unknown';
  }
  return 'Unknown';
}

String jobCustomer(dynamic job) {
  if (job is Map<String, dynamic>) {
    return job['customer_name']?.toString()
        ?? job['customerName']?.toString()
        ?? job['customer']?.toString()
        ?? 'Unknown';
  }
  return 'Unknown';
}

String jobPhone(dynamic job) {
  if (job is Map<String, dynamic>) {
    return job['customer_phone']?.toString()
        ?? job['customerPhone']?.toString()
        ?? job['phone']?.toString()
        ?? '';
  }
  return '';
}

List<String> jobServices(dynamic job) {
  if (job is Map<String, dynamic>) {
    // Backend stores a single service_type enum — convert back to readable label
    final st = job['service_type']?.toString();
    if (st != null && st.isNotEmpty) {
      return [st.replaceAll('_', ' ').split(' ').map((w) =>
          w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ')];
    }
    // Fallback for locally created jobs
    final s = job['services'];
    if (s is List) return s.map((e) => e.toString()).toList();
    if (s is String) return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

String? jobId(dynamic job) {
  if (job is Map<String, dynamic>) return job['id']?.toString() ?? job['jobId']?.toString();
  return null;
}

bool jobIsWhatsApp(dynamic job) {
  if (job is Map<String, dynamic>) {
    final src = job['source']?.toString().toLowerCase() ?? '';
    // NB: match 'whatsapp' only — 'walkin' also contains 'wa', which used to
    // mis-flag every walk-in job as WhatsApp (opened WhatsApp on accept).
    return src.contains('whatsapp');
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────

class QueueBoardScreen extends StatefulWidget {
  const QueueBoardScreen({super.key, required this.apiService, this.role = 'mechanic'});
  final ApiService apiService;
  final String role;

  @override
  State<QueueBoardScreen> createState() => _QueueBoardScreenState();
}

class _QueueBoardScreenState extends State<QueueBoardScreen> {
  static const _filters = ['All', 'In Progress', 'Completed'];

  String _selectedFilter = 'All';
  List<dynamic> _todayJobs = [];
  final List<dynamic> _createdJobs = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _updatingJobId;
  int _selectedIndex = 0;
  Timer? _pollTimer;

  // Cached derived lists — only recomputed when _todayJobs changes
  List<dynamic> _pendingJobs = [];
  List<dynamic> _filteredJobs = [];
  List<dynamic> _pendingAppointments = [];
  String? _updatingAppointmentId;

  @override
  void initState() {
    super.initState();
    _loadJobs();
    // Auto-poll every 30s so WhatsApp-sourced jobs appear automatically
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadJobs());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _recomputeDerived() {
    _pendingJobs = _todayJobs
        .where((j) => jobStatusValue(j).toLowerCase() == 'pending')
        .toList();
    _filteredJobs = _todayJobs.where((j) {
      final status = jobStatusValue(j).toLowerCase();
      // Never show cancelled jobs anywhere on the board
      if (status.contains('cancel')) return false;
      if (_selectedFilter == 'All') return !status.contains('pending');
      if (_selectedFilter == 'In Progress') return status.contains('progress') || status.contains('in_progress');
      if (_selectedFilter == 'Completed') return status.contains('complete') || status.contains('delivered');
      return false;
    }).toList();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiService.getTodayJobs();
      List<dynamic> raw = [];
      if (response is List) {
        raw = response;
      } else if (response is Map<String, dynamic> && response['jobs'] is List) {
        raw = response['jobs'] as List<dynamic>;
      }
      // Strip cancelled jobs — they must not appear on the board
      _todayJobs = raw
          .where((j) => !jobStatusValue(j).toLowerCase().contains('cancel'))
          .toList();
      _attachCreatedJobs();
      _recomputeDerived();

      if (_isOwner) {
        try {
          final appts = await widget.apiService.getAppointments(status: 'pending');
          _pendingAppointments = appts is List ? appts : [];
        } catch (_) {
          _pendingAppointments = [];
        }
      }
    } catch (error) {
      _errorMessage = error is ApiException ? error.toString() : 'Failed to load jobs.';
      _todayJobs = [];
      _recomputeDerived();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _attachCreatedJobs() {
    if (_createdJobs.isEmpty) return;
    final existingIds = _todayJobs.map(jobId).whereType<String>().toSet();
    final newJobs = _createdJobs.where((j) {
      final id = jobId(j);
      return id == null || !existingIds.contains(id);
    }).toList();
    if (newJobs.isNotEmpty) _todayJobs = [..._todayJobs, ...newJobs];
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _updateJobStatus(dynamic job) async {
    final id = jobId(job);
    if (id == null) { _showSnack('Missing job ID.'); return; }
    setState(() => _updatingJobId = id);
    try {
      await widget.apiService.updateJobStatus(id, currentStatus: jobStatusValue(job));
      await _loadJobs();
    } catch (error) {
      _showSnack(error is ApiException ? error.toString() : 'Failed to update status.');
    } finally {
      if (mounted) setState(() => _updatingJobId = null);
    }
  }

  void _openBilling(dynamic job) {
    final id = jobId(job);
    if (id == null) { _showSnack('Missing job ID.'); return; }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BillingScreen(apiService: widget.apiService, jobId: id),
    ));
  }

  void _openCustomerHistory() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CustomerHistoryScreen(apiService: widget.apiService),
    ));
  }

  void _openServiceDetail(dynamic job) {
    final id = jobId(job);
    if (id == null || id.startsWith('local-')) {
      _showSnack('Save the job to the server first before logging details.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ServiceDetailScreen(
        apiService:   widget.apiService,
        jobId:        id,
        serviceType:  job['service_type']?.toString() ?? 'other',
        vehicleReg:   jobVehicle(job),
        customerName: jobCustomer(job),
      ),
    ));
  }

  Future<void> _acceptNewJob(dynamic job) async {
    final id = jobId(job);
    if (id == null || id.startsWith('local-')) {
      _showSnack('Job not saved to server yet — please refresh.');
      return;
    }

    setState(() => _updatingJobId = id);
    try {
      await widget.apiService.updateJobStatus(id, currentStatus: 'pending');
      _showSnack('Job accepted — moved to In Progress.');

      // Only open WhatsApp if it's a WhatsApp-sourced job AND phone looks valid
      final phone = jobPhone(job);
      if (jobIsWhatsApp(job) && phone.length >= 10) {
        final message = Uri.encodeComponent(
          'Hello ${jobCustomer(job)}, your vehicle ${jobVehicle(job)} has been accepted. We will begin work shortly. Thank you!',
        );
        final uri = Uri.parse('https://wa.me/$phone?text=$message');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      _showSnack(error is ApiException ? error.toString() : 'Failed to accept job.');
    } finally {
      if (mounted) setState(() => _updatingJobId = null);
      await _loadJobs();
    }
  }

  Future<void> _acceptAppointment(Map<String, dynamic> appt) async {
    final id = appt['id'].toString();
    setState(() => _updatingAppointmentId = id);
    try {
      await widget.apiService.acceptAppointment(id);
      _showSnack('Appointment accepted — job added to queue.');
    } catch (e) {
      _showSnack(e is ApiException ? e.toString() : 'Failed to accept appointment.');
    } finally {
      if (mounted) setState(() => _updatingAppointmentId = null);
      await _loadJobs();
    }
  }

  Future<void> _rejectAppointment(Map<String, dynamic> appt) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Appointment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject booking for ${appt['customer_name']} (${appt['vehicle_number']})?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason (optional)', hintText: 'e.g. Slot unavailable'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject', style: TextStyle(color: _colorErrorText))),
        ],
      ),
    );
    if (confirmed != true) return;

    final id = appt['id'].toString();
    setState(() => _updatingAppointmentId = id);
    try {
      await widget.apiService.rejectAppointment(id, reason: reasonCtrl.text.trim());
      _showSnack('Appointment rejected.');
    } catch (e) {
      _showSnack(e is ApiException ? e.toString() : 'Failed to reject appointment.');
    } finally {
      if (mounted) setState(() => _updatingAppointmentId = null);
      await _loadJobs();
    }
  }

  Future<void> _cancelJob(dynamic job) async {
    final id = jobId(job);
    if (id == null || id.startsWith('local-')) {
      // Local-only job (not yet saved to server) — just remove from UI
      setState(() {
        _todayJobs.remove(job);
        _createdJobs.removeWhere((c) => jobId(c) == id);
        _recomputeDerived();
      });
      _showSnack('Job removed.');
      return;
    }

    try {
      await widget.apiService.cancelJob(id);
      setState(() {
        _todayJobs.removeWhere((j) => jobId(j) == id);
        _createdJobs.removeWhere((c) => jobId(c) == id);
        _recomputeDerived();
      });
      _showSnack('Job cancelled.');
    } catch (e) {
      _showSnack('Failed to cancel: ${e is ApiException ? e.responseBody : e.toString()}');
    }
  }


  // ─── Add Job Sheet ────────────────────────────────────────────────────────

  Future<void> _showAddJobSheet() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewJobCardScreen(apiService: widget.apiService),
      ),
    );
    if (created == true) _loadJobs();
  }

  // ─── Queue Tab ────────────────────────────────────────────────────────────

  Widget _buildQueueContent() {
    return RefreshIndicator(
      onRefresh: _loadJobs,
      color: _colorPrimary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _FilterRow(
                filters: _filters,
                selected: _selectedFilter,
                onSelect: (f) => setState(() {
                  _selectedFilter = f;
                  _recomputeDerived();
                }),
              ),
            ),
          ),
          if (_errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _ErrorBanner(message: _errorMessage!),
              ),
            ),
          if (_pendingAppointments.isNotEmpty || _pendingJobs.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _SectionHeader(
                  label: 'Awaiting Acceptance',
                  count: _pendingAppointments.length + _pendingJobs.length,
                  color: _colorPending,
                ),
              ),
            ),
            if (_pendingAppointments.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final appt = _pendingAppointments[i] as Map<String, dynamic>;
                      final id = appt['id'].toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AppointmentRequestCard(
                          appt: appt,
                          isUpdating: _updatingAppointmentId == id,
                          onAccept: () => _acceptAppointment(appt),
                          onReject: () => _rejectAppointment(appt),
                        ),
                      );
                    },
                    childCount: _pendingAppointments.length,
                  ),
                ),
              ),
            if (_pendingJobs.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PendingCard(
                        job: _pendingJobs[i],
                        isAccepting: jobId(_pendingJobs[i]) != null && _updatingJobId == jobId(_pendingJobs[i]),
                        onAccept: () => _acceptNewJob(_pendingJobs[i]),
                        onCancel: () => _cancelJob(_pendingJobs[i]),
                      ),
                    ),
                    childCount: _pendingJobs.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
          ],
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredJobs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(
                      _todayJobs.isEmpty ? 'No jobs today' : 'No $_selectedFilter jobs',
                      style: const TextStyle(fontSize: 15, color: Color(0xFF9AA3B0)),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _SectionHeader(label: _selectedFilter, count: _filteredJobs.length, color: _colorPrimary),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _JobCard(
                      job: _filteredJobs[i],
                      isUpdating: jobId(_filteredJobs[i]) != null && _updatingJobId == jobId(_filteredJobs[i]),
                      onUpdateStatus: () => _updateJobStatus(_filteredJobs[i]),
                      onCancel: () => _cancelJob(_filteredJobs[i]),
                      onBilling: () => _openBilling(_filteredJobs[i]),
                      onLogDetails: () => _openServiceDetail(_filteredJobs[i]),
                    ),
                  ),
                  childCount: _filteredJobs.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _isOwner => widget.role == 'owner';

  // ─── Dashboard Tab ────────────────────────────────────────────────────────

  Widget _buildDashboardContent() {
    final total     = _todayJobs.length;
    final queued    = _pendingJobs.length;
    final inProgress = _todayJobs.where((j) {
      final s = jobStatusValue(j).toLowerCase();
      return s.contains('progress') || s.contains('in_progress');
    }).length;
    final completed = _todayJobs.where((j) {
      final s = jobStatusValue(j).toLowerCase();
      return s.contains('complete') || s.contains('delivered');
    }).length;

    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DateHeader(),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: _StatCard(label: 'Total',       value: '$total',      color: _colorPrimary,    icon: Icons.receipt_long_outlined, onTap: () => _goToQueue('All'))),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Queued',      value: '$queued',     color: _colorPending,    icon: Icons.hourglass_empty_rounded, onTap: () => _goToQueue('All'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _StatCard(label: 'In Progress', value: '$inProgress', color: _colorInProgress, icon: Icons.build_outlined, onTap: () => _goToQueue('In Progress'))),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Completed',   value: '$completed',  color: _colorSuccess,    icon: Icons.check_circle_outline_rounded, onTap: () => _goToQueue('Completed'))),
            ]),
            const SizedBox(height: 20),
            if (_isOwner) ...[
              _InventoryShortcut(apiService: widget.apiService),
              const SizedBox(height: 20),
            ],
            _ActivitySection(
              jobs: _todayJobs,
              onViewAll: () => setState(() => _selectedIndex = 0),
            ),
          ],
        ),
      ),
    );
  }

  // Jump to the Queue tab with a status filter pre-applied (from Dashboard cards).
  void _goToQueue(String filter) {
    setState(() {
      _selectedFilter = filter;
      _selectedIndex = 0;
      _recomputeDerived();
    });
  }

  // ─── Owner-only tab stubs ─────────────────────────────────────────────────

  Widget _buildCustomersContent() {
    // CustomerHistoryScreen is a full Scaffold — embed its body content inline
    // by re-using the same widget but wrapped, or just push as a page.
    // For nav-tab experience we inline a lightweight search entry point here.
    return _CustomerTabBody(apiService: widget.apiService);
  }

  Widget _buildReportsContent() {
    return ReportsScreen(apiService: widget.apiService);
  }

  Widget _buildSettingsContent() {
    return SettingsScreen(apiService: widget.apiService);
  }

  // ─── Scaffold ─────────────────────────────────────────────────────────────

  String _tabTitle() {
    if (_isOwner) {
      switch (_selectedIndex) {
        case 0: return 'Queue Board';
        case 1: return 'Dashboard';
        case 2: return 'Customers';
        case 3: return 'Reports';
        case 4: return 'Settings';
      }
    }
    return _selectedIndex == 0 ? 'Queue Board' : 'Dashboard';
  }

  Widget _buildBody() {
    if (_isOwner) {
      switch (_selectedIndex) {
        case 0: return _buildQueueContent();
        case 1: return _buildDashboardContent();
        case 2: return _buildCustomersContent();
        case 3: return _buildReportsContent();
        case 4: return _buildSettingsContent();
      }
    }
    return _selectedIndex == 0 ? _buildQueueContent() : _buildDashboardContent();
  }

  @override
  Widget build(BuildContext context) {
    final showFab          = _selectedIndex == 0;
    final showRefresh      = _selectedIndex == 0;
    final showCustomerIcon = _selectedIndex == 0 && !_isOwner;

    return Scaffold(
      backgroundColor: _colorSurface,
      appBar: AppBar(
        title: Text(_tabTitle()),
        actions: [
          if (showCustomerIcon)
            IconButton(
              icon: const Icon(Icons.people_outline_rounded, size: 22),
              onPressed: _openCustomerHistory,
              tooltip: 'Customer History',
            ),
          if (showRefresh)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: _loadJobs,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _showAddJobSheet,
              backgroundColor: _colorPrimary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('New Job', style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() {
          _selectedIndex = i;
          // Reset to 0 if switching roles mid-session would push index out of range
          if (!_isOwner && _selectedIndex > 1) _selectedIndex = 0;
        }),
        destinations: _isOwner
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.view_list_outlined),
                  selectedIcon: Icon(Icons.view_list_rounded),
                  label: 'Queue',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline_rounded),
                  selectedIcon: Icon(Icons.people_rounded),
                  label: 'Customers',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: 'Reports',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.view_list_outlined),
                  selectedIcon: Icon(Icons.view_list_rounded),
                  label: 'Queue',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Dashboard',
                ),
              ],
      ),
    );
  }
}



// ─── Extracted stateless card widgets ────────────────────────────────────────
// Extracting to separate widgets lets Flutter skip rebuilding them
// when unrelated state changes (e.g. _updatingJobId on a different card).

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.job,
    required this.isAccepting,
    required this.onAccept,
    required this.onCancel,
  });

  final dynamic job;
  final bool isAccepting;
  final VoidCallback onAccept;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final services  = jobServices(job);
    final isWa      = jobIsWhatsApp(job);
    final vehicle   = jobVehicle(job);
    final customer  = jobCustomer(job);
    final phone     = jobPhone(job);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8F2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Icon(Icons.pending_actions_outlined, size: 16, color: _colorPending),
                const SizedBox(width: 6),
                const Text('New Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorPending)),
                const Spacer(),
                isWa
                    ? const _Badge(label: 'WhatsApp', bg: _colorSuccessWa, fg: _colorWhatsAppText)
                    : const _Badge(label: 'Walk-in', bg: _colorInputBg, fg: _colorBodyText),
                const SizedBox(width: 4),
                SizedBox(
                  height: 28, width: 28,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, size: 18, color: _colorMuted),
                    padding: EdgeInsets.zero,
                    onSelected: (v) { if (v == 'cancel') onCancel(); },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'cancel', child: Text('Remove', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vehicle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _colorHeading, letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(customer, style: const TextStyle(fontSize: 14, color: _colorBodyText)),
                        ],
                      ),
                    ),
                    if (phone.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Icon(Icons.phone_outlined, size: 14, color: _colorMuted),
                          const SizedBox(height: 2),
                          Text(phone, style: const TextStyle(fontSize: 12, color: _colorMuted)),
                        ],
                      ),
                  ],
                ),
                if (services.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: services.map((s) => _ServiceChip(label: s)).toList()),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isAccepting ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _colorSuccess,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                    child: isAccepting
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 18),
                              SizedBox(width: 6),
                              Text('Accept Job', style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _serviceTypeLabels = {
  'car_wash':        'Car Wash',
  'tyre_change':     'Tyre Change',
  'wheel_alignment': 'Wheel Alignment',
  'wheel_balancing': 'Wheel Balancing',
  'water_wash':      'Water Wash',
  'full_service':    'Full Service',
  'other':           'Other Service',
};

class _AppointmentRequestCard extends StatelessWidget {
  const _AppointmentRequestCard({
    required this.appt,
    required this.isUpdating,
    required this.onAccept,
    required this.onReject,
  });

  final Map<String, dynamic> appt;
  final bool isUpdating;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final name    = appt['customer_name']?.toString() ?? '—';
    final phone   = appt['phone']?.toString() ?? '';
    final vehicle = appt['vehicle_number']?.toString() ?? '—';
    final type    = appt['service_type']?.toString();
    final service = _serviceTypeLabels[type] ?? (type ?? 'Other');
    final issue   = appt['issue']?.toString();
    final lang    = (appt['language_pref']?.toString() ?? 'EN').toUpperCase();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8F2),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_note_outlined, size: 16, color: _colorPending),
                const SizedBox(width: 6),
                const Text('Appointment Request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _colorPending)),
                const Spacer(),
                _Badge(label: lang, bg: const Color(0x1A2980B9), fg: _colorInProgress),
                const SizedBox(width: 4),
                const _Badge(label: 'WhatsApp', bg: _colorSuccessWa, fg: _colorWhatsAppText),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vehicle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _colorHeading, letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(name, style: const TextStyle(fontSize: 14, color: _colorBodyText)),
                        ],
                      ),
                    ),
                    if (phone.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Icon(Icons.phone_outlined, size: 14, color: _colorMuted),
                          const SizedBox(height: 2),
                          Text(phone, style: const TextStyle(fontSize: 12, color: _colorMuted)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [_ServiceChip(label: service)]),
                if (issue != null && issue.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(issue, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: isUpdating ? null : onReject,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _colorErrorText),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.close_rounded, size: 18, color: _colorErrorText),
                              SizedBox(width: 6),
                              Text('Reject', style: TextStyle(fontWeight: FontWeight.w600, color: _colorErrorText)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: isUpdating ? null : onAccept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _colorSuccess,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                          ),
                          child: isUpdating
                              ? const SizedBox(height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_rounded, size: 18),
                                    SizedBox(width: 6),
                                    Text('Accept', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.isUpdating,
    required this.onUpdateStatus,
    required this.onCancel,
    required this.onBilling,
    required this.onLogDetails,
  });

  final dynamic job;
  final bool isUpdating;
  final VoidCallback onUpdateStatus;
  final VoidCallback onCancel;
  final VoidCallback onBilling;
  final VoidCallback onLogDetails;

  @override
  Widget build(BuildContext context) {
    final status      = jobStatusValue(job);
    final services    = jobServices(job);
    final vehicle     = jobVehicle(job);
    final customer    = jobCustomer(job);
    final phone       = jobPhone(job);
    final sColor      = _statusColor(status);
    final sBgColor    = _statusBgColor(status);
    final sLabel      = _statusLabel(status);

    // Use Stack for the coloured left accent — non-uniform Border + borderRadius
    // is not supported by Flutter, so we overlay the accent as a Positioned child.
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              border: Border.all(color: _colorBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(vehicle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _colorHeading, letterSpacing: 0.4)),
                            const SizedBox(height: 2),
                            Text(customer, style: const TextStyle(fontSize: 13, color: _colorBodyText)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: isUpdating ? null : onUpdateStatus,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: sBgColor, borderRadius: const BorderRadius.all(Radius.circular(8))),
                              child: isUpdating
                                  ? SizedBox(height: 14, width: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: sColor))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(width: 6, height: 6,
                                            decoration: BoxDecoration(color: sColor, shape: BoxShape.circle)),
                                        const SizedBox(width: 5),
                                        Text(sLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sColor)),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          SizedBox(
                            height: 28, width: 28,
                            child: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz, size: 18, color: _colorMuted),
                              padding: EdgeInsets.zero,
                              onSelected: (v) {
                                if (v == 'cancel')     onCancel();
                                if (v == 'billing')    onBilling();
                                if (v == 'details')    onLogDetails();
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'details', child: Text('Log Details')),
                                PopupMenuItem(value: 'billing', child: Text('Generate Invoice')),
                                PopupMenuItem(value: 'cancel',  child: Text('Remove', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (services.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: services.map((s) => _ServiceChip(label: s)).toList()),
                  ],
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.phone_outlined, size: 12, color: _colorMuted),
                      const SizedBox(width: 4),
                      Text(phone, style: const TextStyle(fontSize: 12, color: _colorMuted)),
                    ]),
                  ],
                ],
              ),
            ),
          ),
          // Coloured left accent bar
          Positioned(
            left: 0, top: 0, bottom: 0,
            child: Container(width: 4, color: sColor),
          ),
        ],
      ),
    );
  }
}

// ─── Small stateless widgets ──────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filters, required this.selected, required this.onSelect});
  final List<String> filters;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final sel = selected == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _colorPrimary : Colors.white,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  border: Border.fromBorderSide(BorderSide(color: sel ? _colorPrimary : const Color(0xFFE0E4EA))),
                ),
                child: Text(f,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: sel ? Colors.white : _colorBodyText),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.all(Radius.circular(2)))),
      const SizedBox(width: 8),
      Text('$label  •  $count',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorBodyText, letterSpacing: 0.2)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.color, required this.icon, this.onTap});
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, color: _colorSubtext)),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: color, letterSpacing: -1)),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: card,
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.jobs, required this.onViewAll});
  final List<dynamic> jobs;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Today's Activity",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
          const SizedBox(height: 16),
          if (jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No jobs recorded today.', style: TextStyle(fontSize: 14, color: _colorSubtext)),
            )
          else ...[
            ...jobs.take(5).map((job) {
              final status = jobStatusValue(job);
              return _ActivityRow(
                vehicle: jobVehicle(job),
                customer: jobCustomer(job),
                status: _statusLabel(status),
                statusColor: _statusColor(status),
              );
            }),
            if (jobs.length > 5) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onViewAll,
                child: const Text('View all in Queue →',
                  style: TextStyle(fontSize: 13, color: _colorPrimary, fontWeight: FontWeight.w500)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _InventoryShortcut extends StatelessWidget {
  const _InventoryShortcut({required this.apiService});
  final ApiService apiService;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Inventory',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
          const SizedBox(height: 8),
          _InventoryTile(
            icon: Icons.tire_repair,
            label: 'Tyre Stock',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => TyreStockScreen(apiService: apiService))),
          ),
          _InventoryTile(
            icon: Icons.inventory_2_outlined,
            label: 'Parts Inventory',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => InventoryScreen(apiService: apiService))),
          ),
        ],
      ),
    );
  }
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _colorPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _colorHeading)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: _colorSubtext),
          ],
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader();

  static const _days   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  static const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_days[now.weekday - 1],
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _colorHeading, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text('${now.day} ${_months[now.month - 1]} ${now.year}',
          style: const TextStyle(fontSize: 14, color: _colorSubtext)),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.vehicle, required this.customer, required this.status, required this.statusColor});
  final String vehicle;
  final String customer;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(vehicle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _colorHeading))),
        Text(customer, style: const TextStyle(fontSize: 13, color: _colorSubtext)),
        const SizedBox(width: 10),
        Text(status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const BoxDecoration(
        color: _colorInputBg,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: _colorBodyText, fontWeight: FontWeight.w500)),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.bg, required this.fg});
  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(6))),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w500)),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: _colorErrorBg,
        borderRadius: BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(BorderSide(color: _colorErrorBorder)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: _colorErrorText),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: _colorErrorText))),
      ]),
    );
  }
}


class _CustomerTabBody extends StatelessWidget {
  const _CustomerTabBody({required this.apiService});
  final ApiService apiService;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline_rounded, size: 52, color: Color(0xFFD0D5DD)),
            const SizedBox(height: 16),
            const Text('Customer History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1A2332))),
            const SizedBox(height: 6),
            const Text('Search customers and view their service history.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFF9AA3B0))),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CustomerHistoryScreen(apiService: apiService),
                )),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Search Customers'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

