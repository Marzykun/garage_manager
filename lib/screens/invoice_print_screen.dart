import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'package:garage_manager/services/api_service.dart';
import 'package:garage_manager/services/invoice_pdf.dart';

/// Full-page preview of the printable invoice with Print and Share actions.
/// Print goes through Android's print system (Wi-Fi/Bluetooth printers with a
/// print service installed, or "Save as PDF").
class InvoicePrintScreen extends StatefulWidget {
  const InvoicePrintScreen({super.key, required this.apiService, required this.invoiceId});

  final ApiService apiService;
  final String invoiceId;

  @override
  State<InvoicePrintScreen> createState() => _InvoicePrintScreenState();
}

class _InvoicePrintScreenState extends State<InvoicePrintScreen> {
  Uint8List? _pdf;
  String _fileName = 'invoice';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _pdf = null; _error = null; });
    try {
      final data  = await widget.apiService.getInvoicePrintData(widget.invoiceId);
      final bytes = await InvoicePdf.build(data);
      if (!mounted) return;
      setState(() {
        _pdf = bytes;
        _fileName = InvoicePdf.invoiceNumber((data['invoice'] as Map).cast<String, dynamic>());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.toString() : 'Could not prepare the invoice. ($e)');
    }
  }

  Future<void> _print() async {
    final bytes = _pdf;
    if (bytes == null) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName);
  }

  Future<void> _share() async {
    final bytes = _pdf;
    if (bytes == null) return;
    await Printing.sharePdf(bytes: bytes, filename: '$_fileName.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final ready = _pdf != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(ready ? _fileName : 'Invoice'),
        actions: [
          IconButton(
            tooltip: 'Print',
            onPressed: ready ? _print : null,
            icon: const Icon(Icons.print_rounded),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFE53935))),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ]),
              ),
            )
          : !ready
              ? const Center(child: CircularProgressIndicator())
              : PdfPreview(
                  build: (_) => _pdf!,
                  useActions: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: '$_fileName.pdf',
                ),
      bottomNavigationBar: ready
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Share PDF'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _print,
                        icon: const Icon(Icons.print_rounded, size: 20),
                        label: const Text('Print Invoice'),
                      ),
                    ),
                  ),
                ]),
              ),
            )
          : null,
    );
  }
}
