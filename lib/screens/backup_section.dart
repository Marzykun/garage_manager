import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:garage_manager/services/api_service.dart';

const _colorPrimary = Color(0xFF2D3A4A);
const _colorHeading = Color(0xFF1A2332);
const _colorSubtext = Color(0xFF7A869A);
const _colorBorder  = Color(0xFFE8EAED);
const _colorGood    = Color(0xFF27AE60);
const _colorWarn    = Color(0xFFB9770E);
const _colorDanger  = Color(0xFFE53935);

/// Settings card for database backups: status of the monthly automatic
/// backup, "Back Up Now", and per-backup Share (send a copy off the phone)
/// and Restore.
class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.apiService});
  final ApiService apiService;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  static final _dateFmt = DateFormat('dd MMM yyyy, h:mm a');

  Map<String, dynamic>? _status;
  String? _error;
  bool _busy = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.apiService.getBackups();
      if (mounted) setState(() { _status = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.toString() : 'Could not load backups.');
    }
  }

  List<Map<String, dynamic>> get _backups =>
      ((_status?['backups'] as List?) ?? []).cast<Map>().map((m) => m.cast<String, dynamic>()).toList();

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      await widget.apiService.createBackup();
      await _load();
      _snack('Backup saved.');
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Backup failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(Map<String, dynamic> b) async {
    setState(() => _busy = true);
    try {
      final bytes = await widget.apiService.downloadBackup(b['name']);
      final file = File('${(await getTemporaryDirectory()).path}/${b['name']}');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Garage Manager backup — ${_fmt(b['created_at'])}',
        text: 'Garage Manager data backup from ${_fmt(b['created_at'])}. Keep this file safe.',
      ));
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Could not share the backup. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'All current data (jobs, customers, invoices, stock) will be replaced with '
          'the backup from ${_fmt(b['created_at'])}.\n\n'
          'Anything entered after that date will be lost. A safety copy of the '
          'current data is saved first, so this can be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _colorDanger),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await widget.apiService.restoreBackup(b['name']);
      await _load();
      _snack('Data restored from ${_fmt(b['created_at'])}. A safety copy of the previous data was kept.');
    } catch (e) {
      _snack(e is ApiException ? e.toString() : 'Restore failed — your data was not changed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmt(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    return d == null ? '—' : _dateFmt.format(d.toLocal());
  }

  String _size(dynamic bytes) {
    final b = (bytes as num?)?.toDouble() ?? 0;
    return b >= 1024 * 1024 ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';
  }

  String _kindLabel(String? kind) => switch (kind) {
        'auto'        => 'Automatic',
        'pre-restore' => 'Safety copy',
        _             => 'Manual',
      };

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final interval = s?['interval_days'] ?? 30;
    final keep = s?['keep'] ?? 12;
    final last = (s?['last_backup'] as Map?)?.cast<String, dynamic>();
    final shared = s?['shared'] == true;
    final backups = _backups;
    final visible = _showAll ? backups : backups.take(3).toList();

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
          const Text('Data Backup',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _colorHeading)),
          const SizedBox(height: 4),
          Text('Automatic backup every $interval days · keeps the last $keep',
              style: const TextStyle(fontSize: 12, color: _colorSubtext)),
          const SizedBox(height: 16),

          if (_error != null && s == null) ...[
            Text(_error!, style: const TextStyle(fontSize: 13, color: _colorDanger)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ] else if (s == null)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else ...[
            _StatusRow(
              icon: last == null ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
              color: last == null ? _colorWarn : _colorGood,
              text: last == null ? 'No backup yet' : 'Last backup: ${_fmt(last['created_at'])}',
            ),
            if (s['next_due'] != null)
              _StatusRow(
                icon: Icons.schedule_rounded,
                color: _colorSubtext,
                text: 'Next automatic: ${DateFormat('dd MMM yyyy').format(DateTime.parse(s['next_due']).toLocal())}',
              ),
            _StatusRow(
              icon: shared ? Icons.phone_android_rounded : Icons.warning_amber_rounded,
              color: shared ? _colorGood : _colorWarn,
              text: shared
                  ? 'Saved in phone storage → GarageManager/backups'
                  : 'Saved inside Termux only. Run "termux-setup-storage" in Termux once '
                    'so backups go to phone storage and survive a Termux reinstall.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _backupNow,
                icon: _busy
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.backup_rounded, size: 18),
                label: const Text('Back Up Now'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tip: once a month, tap Share on the newest backup and send it to WhatsApp '
              'or Google Drive, so a copy exists even if this phone is lost or broken.',
              style: TextStyle(fontSize: 12, color: _colorSubtext, height: 1.4),
            ),
            if (backups.isNotEmpty) ...[
              const Divider(height: 28),
              for (final b in visible)
                _BackupTile(
                  title: _fmt(b['created_at']),
                  subtitle: '${_kindLabel(b['kind'])} · ${_size(b['size'])}',
                  enabled: !_busy,
                  onShare: () => _share(b),
                  onRestore: () => _restore(b),
                ),
              if (backups.length > 3)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? 'Show fewer' : 'Show all ${backups.length} backups'),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: _colorHeading))),
        ]),
      );
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onShare,
    required this.onRestore,
  });
  final String title, subtitle;
  final bool enabled;
  final VoidCallback onShare, onRestore;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 20, color: _colorPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _colorHeading)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: _colorSubtext)),
            ]),
          ),
          IconButton(
            tooltip: 'Share (WhatsApp, Drive…)',
            onPressed: enabled ? onShare : null,
            icon: const Icon(Icons.share_rounded, size: 20),
          ),
          IconButton(
            tooltip: 'Restore',
            onPressed: enabled ? onRestore : null,
            icon: const Icon(Icons.settings_backup_restore_rounded, size: 20),
          ),
        ]),
      );
}
