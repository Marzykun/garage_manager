import 'dart:async';

import 'package:flutter/material.dart';
import 'package:garage_manager/services/api_service.dart';
import 'package:garage_manager/services/termux_service.dart';

import 'queue_board_screen.dart';

enum _ServerStatus { checking, online, offline }

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
  bool _obscurePassword = true;

  _ServerStatus _serverStatus = _ServerStatus.checking;
  bool _startingServer = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _checkServerStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkServerStatus() async {
    final up = await widget.apiService.pingServer();
    if (!mounted) return;
    setState(() => _serverStatus = up ? _ServerStatus.online : _ServerStatus.offline);
  }

  Future<void> _startServer() async {
    setState(() => _startingServer = true);
    try {
      await TermuxService.startBackendServer();
      await _showSnackBar('Start command sent to Termux — waiting for the server…');
    } catch (e) {
      await _showSnackBar(e.toString());
      if (mounted) setState(() => _startingServer = false);
      return;
    }

    // Poll every 2s for up to ~20s while the backend (and Postgres, if it
    // was also down) comes up.
    var attempts = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      final up = await widget.apiService.pingServer();
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (up) {
        timer.cancel();
        setState(() {
          _serverStatus = _ServerStatus.online;
          _startingServer = false;
        });
        await _showSnackBar('Server is up.');
      } else if (attempts >= 10) {
        timer.cancel();
        setState(() {
          _serverStatus = _ServerStatus.offline;
          _startingServer = false;
        });
        await _showSnackBar('Server still not responding. Check Termux on the phone.');
      }
    });
  }

  Future<void> _showSnackBar(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();  // blank = mechanic login
    final password = _passwordController.text;          // don't trim — password may have spaces

    if (password.isEmpty) {
      await _showSnackBar('Password is required.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await widget.apiService.login(username, password);

      final role = (result is Map<String, dynamic>)
          ? (result['role']?.toString() ?? 'mechanic')
          : 'mechanic';

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => QueueBoardScreen(apiService: widget.apiService, role: role),
        ),
      );
    } catch (error) {
      final errorMessage = error is ApiException
          ? error.toString()
          : 'Login failed. Check your credentials. ($error)';
      await _showSnackBar(errorMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildServerStatus(),
                const SizedBox(height: 24),
                _buildForm(),
                const SizedBox(height: 24),
                _buildLoginButton(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF2D3A4A),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.car_repair_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Garage Manager',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A2332),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Mechanic: leave username blank\nOwner: enter username + password',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF7A869A),
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildServerStatus() {
    final Color dotColor;
    final String label;
    switch (_serverStatus) {
      case _ServerStatus.online:
        dotColor = const Color(0xFF2E7D32);
        label = 'Server online';
        break;
      case _ServerStatus.offline:
        dotColor = const Color(0xFFE53935);
        label = 'Server not responding';
        break;
      case _ServerStatus.checking:
        dotColor = const Color(0xFF7A869A);
        label = 'Checking server…';
        break;
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7A869A))),
          ],
        ),
        if (_serverStatus == _ServerStatus.offline) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: _startingServer ? null : _startServer,
              icon: _startingServer
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.power_settings_new_rounded, size: 16),
              label: Text(_startingServer ? 'Starting…' : 'Start Server'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        TextField(
          controller: _usernameController,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: null,         // disables autofill — prevents phone secretly filling this
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A2332)),
          decoration: const InputDecoration(
            labelText: 'Username (owner only — leave blank for mechanic)',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20, color: Color(0xFF7A869A)),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A2332)),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF7A869A)),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: const Color(0xFF7A869A),
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text('Sign In'),
      ),
    );
  }
}
