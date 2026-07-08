import 'package:flutter/material.dart';
import 'package:garage_manager/services/api_service.dart';
import 'package:garage_manager/screens/tyre_stock_screen.dart';
import 'package:garage_manager/screens/inventory_screen.dart';

const _colorPrimary   = Color(0xFF2D3A4A);
const _colorHeading   = Color(0xFF1A2332);
const _colorSubtext   = Color(0xFF7A869A);
const _colorBorder    = Color(0xFFE8EAED);
const _colorErrorText = Color(0xFFE53935);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  bool _saving  = false;
  String? _error;

  // Garage info
  final _nameCtrl        = TextEditingController();
  final _openCtrl        = TextEditingController();
  final _closeCtrl       = TextEditingController();
  final _workingDaysCtrl = TextEditingController();
  final _gstCtrl         = TextEditingController();

  // Mechanic password
  final _mechNewCtrl     = TextEditingController();
  final _mechConfirmCtrl = TextEditingController();
  bool _mechObscure      = true;

  // Owner credentials
  final _ownerUserCtrl    = TextEditingController();
  final _ownerNewCtrl     = TextEditingController();
  final _ownerConfirmCtrl = TextEditingController();
  bool _ownerObscure      = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _openCtrl.dispose(); _closeCtrl.dispose();
    _workingDaysCtrl.dispose(); _gstCtrl.dispose();
    _mechNewCtrl.dispose(); _mechConfirmCtrl.dispose();
    _ownerUserCtrl.dispose(); _ownerNewCtrl.dispose(); _ownerConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await widget.apiService.getSettings();
      final data = (resp as Map<String, dynamic>?)?['data'] as Map<String, dynamic>? ?? {};
      _nameCtrl.text        = data['garage_name']  ?? '';
      _openCtrl.text        = data['open_time']    ?? '09:00';
      _closeCtrl.text       = data['close_time']   ?? '20:00';
      _workingDaysCtrl.text = data['working_days'] ?? 'Mon-Sat';
      _gstCtrl.text         = (data['gst_percent'] ?? 18).toString();
    } catch (e) {
      _error = e is ApiException ? e.toString() : 'Failed to load settings.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveGarageInfo() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { _snack('Garage name is required.'); return; }
    final gst = double.tryParse(_gstCtrl.text.trim()) ?? 18;

    setState(() => _saving = true);
    try {
      await widget.apiService.updateSettings(
        garageName:  name,
        openTime:    _openCtrl.text.trim(),
        closeTime:   _closeCtrl.text.trim(),
        workingDays: _workingDaysCtrl.text.trim(),
        gstPercent:  gst,
      );
      _snack('Garage info saved.');
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Failed to save.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveMechanicPassword() async {
    final np = _mechNewCtrl.text;
    final cp = _mechConfirmCtrl.text;
    if (np.isEmpty || cp.isEmpty) { _snack('Both password fields are required.'); return; }

    setState(() => _saving = true);
    try {
      await widget.apiService.updateGaragePassword(newPassword: np, confirmPassword: cp);
      _mechNewCtrl.clear(); _mechConfirmCtrl.clear();
      _snack('Mechanic password updated.');
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Failed to update password.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveOwnerCredentials() async {
    final user = _ownerUserCtrl.text.trim();
    final np   = _ownerNewCtrl.text;
    final cp   = _ownerConfirmCtrl.text;
    if (user.isEmpty || np.isEmpty || cp.isEmpty) { _snack('All fields are required.'); return; }

    setState(() => _saving = true);
    try {
      await widget.apiService.updateOwnerCredentials(
          username: user, newPassword: np, confirmPassword: cp);
      _ownerNewCtrl.clear(); _ownerConfirmCtrl.clear();
      _snack('Owner credentials updated.');
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Failed to update credentials.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: _colorErrorText)))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildQuickLinks(),
                  const SizedBox(height: 20),
                  _buildGarageInfoSection(),
                  const SizedBox(height: 20),
                  _buildMechanicPasswordSection(),
                  const SizedBox(height: 20),
                  _buildOwnerCredentialsSection(),
                  const SizedBox(height: 40),
                ],
              );
  }

  // ── Quick Links ───────────────────────────────────────────────────────────

  Widget _buildQuickLinks() {
    return _Section(
      title: 'Inventory',
      children: [
        _NavTile(
          icon: Icons.tire_repair,
          label: 'Tyre Stock',
          subtitle: 'View, add, and edit tyre inventory',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TyreStockScreen(apiService: widget.apiService),
            ),
          ),
        ),
        _NavTile(
          icon: Icons.inventory_2_outlined,
          label: 'Parts Inventory',
          subtitle: 'Manage parts, fluids, and consumables',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InventoryScreen(apiService: widget.apiService),
            ),
          ),
        ),
      ],
    );
  }

  // ── Garage Info ───────────────────────────────────────────────────────────

  Widget _buildGarageInfoSection() {
    return _Section(
      title: 'Garage Info',
      children: [
        _Field(ctrl: _nameCtrl, label: 'Garage Name'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Field(ctrl: _openCtrl,  label: 'Open Time',  hint: '09:00')),
          const SizedBox(width: 12),
          Expanded(child: _Field(ctrl: _closeCtrl, label: 'Close Time', hint: '20:00')),
        ]),
        const SizedBox(height: 12),
        _Field(ctrl: _workingDaysCtrl, label: 'Working Days', hint: 'e.g. Mon-Sat'),
        const SizedBox(height: 12),
        _Field(ctrl: _gstCtrl, label: 'GST %', hint: '18',
            type: const TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 16),
        _SaveButton(label: 'Save Garage Info', saving: _saving, onPressed: _saveGarageInfo),
      ],
    );
  }

  // ── Mechanic Password ─────────────────────────────────────────────────────

  Widget _buildMechanicPasswordSection() {
    return _Section(
      title: 'Mechanic Password',
      subtitle: 'Shared password all mechanics use to log in.',
      children: [
        _PasswordField(ctrl: _mechNewCtrl,     label: 'New Password',     obscure: _mechObscure,  onToggle: () => setState(() => _mechObscure = !_mechObscure)),
        const SizedBox(height: 12),
        _PasswordField(ctrl: _mechConfirmCtrl, label: 'Confirm Password', obscure: _mechObscure,  onToggle: () => setState(() => _mechObscure = !_mechObscure)),
        const SizedBox(height: 16),
        _SaveButton(label: 'Update Mechanic Password', saving: _saving, onPressed: _saveMechanicPassword),
      ],
    );
  }

  // ── Owner Credentials ─────────────────────────────────────────────────────

  Widget _buildOwnerCredentialsSection() {
    return _Section(
      title: 'Owner Credentials',
      subtitle: 'Update the username and password for the owner login.',
      children: [
        _Field(ctrl: _ownerUserCtrl, label: 'Username'),
        const SizedBox(height: 12),
        _PasswordField(ctrl: _ownerNewCtrl,     label: 'New Password',     obscure: _ownerObscure, onToggle: () => setState(() => _ownerObscure = !_ownerObscure)),
        const SizedBox(height: 12),
        _PasswordField(ctrl: _ownerConfirmCtrl, label: 'Confirm Password', obscure: _ownerObscure, onToggle: () => setState(() => _ownerObscure = !_ownerObscure)),
        const SizedBox(height: 16),
        _SaveButton(label: 'Update Owner Credentials', saving: _saving, onPressed: _saveOwnerCredentials),
      ],
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: _colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.ctrl, required this.label, this.hint, this.type = TextInputType.text});
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final TextInputType type;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: _colorSubtext),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.ctrl, required this.label, required this.obscure, required this.onToggle});
  final TextEditingController ctrl;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14, color: _colorHeading),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20, color: _colorSubtext),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.label, required this.subtitle, required this.onTap});
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: _colorPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _colorHeading)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _colorSubtext),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.label, required this.saving, required this.onPressed});
  final String label;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: saving ? null : onPressed,
        child: saving
            ? const SizedBox(height: 20, width: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(label),
      ),
    );
  }
}
