import 'package:flutter/material.dart';

import 'api_service.dart';

//change

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garage Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: LoginScreen(apiService: ApiService()),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _showSnackBar(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
    });

    try {
      //change nigesh
      await Future.delayed(const Duration(milliseconds: 500));
      // await widget.apiService.login(
      //   _usernameController.text.trim(),
      //   _passwordController.text,
      // );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(apiService: widget.apiService),
        ),
      );
    } catch (error) {
      final errorMessage = error is ApiException
          ? error.toString()
          : 'Login failed. ${error.toString()}';
      await _showSnackBar(errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Column(
                  children: const [
                    Icon(Icons.garage, size: 92, color: Colors.blueGrey),
                    SizedBox(height: 16),
                    Text(
                      'Garage Manager',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Login to access your dashboard',
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _usernameController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
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
                      : const Text('Login'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _isRefreshing = false;
  List<dynamic> _todayJobs = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchTodayJobs();
  }

  String get _formattedDate {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchTodayJobs() async {
    setState(() {
      _isRefreshing = true;
      _errorMessage = '';
    });

    try {
      final result = await widget.apiService.getTodayJobs();
      if (result is List) {
        setState(() {
          _todayJobs = result;
        });
      } else if (result is Map<String, dynamic> && result['jobs'] is List) {
        setState(() {
          _todayJobs = result['jobs'] as List<dynamic>;
        });
      } else {
        setState(() {
          _todayJobs = [];
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = error is ApiException
            ? error.toString()
            : 'Failed to load jobs.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  int _countByStatus(String status) {
    final normalized = status.toLowerCase();
    return _todayJobs.where((job) {
      final value = job is Map ? job['status'] : null;
      if (value == null) return false;
      final jobStatus = value.toString().toLowerCase();
      if (normalized == 'total') return true;
      if (normalized == 'in queue') {
        return jobStatus == 'queued' ||
            jobStatus == 'pending' ||
            jobStatus == 'waiting';
      }
      if (normalized == 'in progress') {
        return jobStatus == 'in_progress' ||
            jobStatus == 'progress' ||
            jobStatus == 'ongoing';
      }
      if (normalized == 'completed') {
        return jobStatus == 'completed' || jobStatus == 'done';
      }
      return false;
    }).length;
  }

  Widget _buildSummaryCard(String title, int count, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 26,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentJobs() {
    final recentJobs = _todayJobs.reversed.take(5).toList();
    if (recentJobs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No recent jobs found.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Column(
      children: recentJobs.map((job) {
        final jobMap = job is Map<String, dynamic> ? job : <String, dynamic>{};
        final vehicle = jobMap['vehicleReg']?.toString() ?? 'Unknown vehicle';
        final customer =
            jobMap['customerName']?.toString() ?? 'Unknown customer';
        final status = jobMap['status']?.toString() ?? 'Unknown';
        final badgeColor = _statusBadgeColor(status);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text(vehicle),
            subtitle: Text(customer),
            trailing: Chip(
              backgroundColor: badgeColor.withOpacity(0.16),
              label: Text(status, style: TextStyle(color: badgeColor)),
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _statusBadgeColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('completed') || normalized.contains('done')) {
      return Colors.green;
    }
    if (normalized.contains('progress') || normalized.contains('ongoing')) {
      return Colors.orange;
    }
    if (normalized.contains('queue') ||
        normalized.contains('pending') ||
        normalized.contains('waiting')) {
      return Colors.blueGrey;
    }
    return Colors.black54;
  }

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _fetchTodayJobs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Hello, Garage Manager',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Today: $_formattedDate',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildSummaryCard(
                'Total Vehicles Today',
                _todayJobs.length,
                Colors.blue,
              ),
              _buildSummaryCard(
                'In Queue',
                _countByStatus('in queue'),
                Colors.indigo,
              ),
              _buildSummaryCard(
                'In Progress',
                _countByStatus('in progress'),
                Colors.orange,
              ),
              _buildSummaryCard(
                'Completed',
                _countByStatus('completed'),
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Recent Jobs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          _buildRecentJobs(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPlaceholderTab(String title) {
    return RefreshIndicator(
      onRefresh: _fetchTodayJobs,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('Pull down to refresh the dashboard data.'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildDashboardTab(),
      _buildPlaceholderTab('Jobs'),
      _buildPlaceholderTab('History'),
      _buildPlaceholderTab('Billing'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Garage Manager'),
            Text(
              'Today: $_formattedDate',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: _isRefreshing && _todayJobs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Jobs'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Billing',
          ),
        ],
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
