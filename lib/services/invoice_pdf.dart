import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a printable A4 invoice from the `/api/invoices/:id/print` payload:
/// `{ invoice: {...}, garage: {...}, tyres: [...], parts_used: [...] }`.
///
/// Line items always add up to the saved invoice: labour, then the logged
/// tyres (when they account for the parts charge), with any remainder shown as
/// "Other parts & consumables".
class InvoicePdf {
  static const _ink     = PdfColor.fromInt(0xFF1A2332);
  static const _muted   = PdfColor.fromInt(0xFF5A6578);
  static const _rule    = PdfColor.fromInt(0xFFD5D9E0);
  static const _band    = PdfColor.fromInt(0xFFF0F2F5);
  static const _brand   = PdfColor.fromInt(0xFF2D3A4A);
  static const _paid    = PdfColor.fromInt(0xFF1E8449);
  static const _pending = PdfColor.fromInt(0xFFB9770E);

  static final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final _date  = DateFormat('dd MMM yyyy');

  static String invoiceNumber(Map<String, dynamic> invoice) {
    final n = invoice['invoice_no'];
    return n == null ? '—' : 'INV-${n.toString().padLeft(4, '0')}';
  }

  static Future<Uint8List> build(Map<String, dynamic> data) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold    = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));

    final inv    = (data['invoice'] as Map).cast<String, dynamic>();
    final garage = (data['garage']  as Map? ?? {}).cast<String, dynamic>();
    final tyres  = (data['tyres']   as List? ?? []).cast<Map>();
    final partsUsed = (data['parts_used'] as List? ?? []).map((e) => e.toString()).toList();

    final labour   = _num(inv['labour_charge']);
    final parts    = _num(inv['parts_charge']);
    final gstPct   = _num(inv['gst_percent']);
    final gst      = _num(inv['gst_amount']);
    final discount = _num(inv['discount']);
    final total    = _num(inv['total_amount']);
    final subTotal = labour + parts;

    final gstin  = (garage['gstin'] ?? '').toString().trim();
    final isTaxInvoice = gstin.isNotEmpty;
    final garageName = _str(garage['garage_name'], 'My Garage');
    final isPaid = inv['payment_status'] == 'paid';

    final items = _lineItems(
      service: _serviceLabel(inv['service_type']?.toString()),
      labour: labour,
      parts: parts,
      tyres: tyres,
      partsUsed: partsUsed,
    );

    final doc = pw.Document(
      title: '${invoiceNumber(inv)} — $garageName',
      author: garageName,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: _muted)),
        ),
        build: (ctx) => [
          _header(garage, garageName, gstin, isTaxInvoice, inv),
          pw.SizedBox(height: 18),
          _parties(inv),
          pw.SizedBox(height: 18),
          _itemsTable(items),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _label('Amount in words'),
                    pw.SizedBox(height: 3),
                    pw.Text(_amountInWords(total),
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 14),
                    _label('Payment'),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      isPaid
                          ? 'PAID${_paymentLabel(inv['payment_method']) != null ? ' — ${_paymentLabel(inv['payment_method'])}' : ''}'
                          : 'PENDING',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: isPaid ? _paid : _pending,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                flex: 4,
                child: _totals(
                  subTotal: subTotal,
                  gstPct: gstPct,
                  gst: gst,
                  discount: discount,
                  total: total,
                  splitGst: isTaxInvoice,
                ),
              ),
            ],
          ),
          if (_str(inv['job_notes'], '').isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _label('Notes'),
            pw.SizedBox(height: 3),
            pw.Text(_str(inv['job_notes'], ''), style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
          ],
          pw.SizedBox(height: 36),
          _signOff(garageName),
        ],
      ),
    );

    return doc.save();
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  static pw.Widget _header(Map<String, dynamic> garage, String garageName, String gstin,
      bool isTaxInvoice, Map<String, dynamic> inv) {
    final address = _str(garage['address'], '');
    final phone   = _str(garage['phone'], '');

    return pw.Column(children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(garageName,
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _brand)),
                if (address.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(address, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
                ],
                if (phone.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
                ],
                if (gstin.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text('GSTIN: $gstin',
                      style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink)),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(isTaxInvoice ? 'TAX INVOICE' : 'INVOICE',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink, letterSpacing: 1)),
              pw.SizedBox(height: 8),
              _kv('Invoice No', invoiceNumber(inv)),
              _kv('Date', _fmtDate(inv['created_at'])),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Container(height: 2, color: _brand),
    ]);
  }

  static pw.Widget _parties(Map<String, dynamic> inv) {
    final vehicleDesc = [inv['brand'], inv['model']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' ');
    final km = int.tryParse(inv['km_run']?.toString() ?? '') ?? 0;

    pw.Widget box(String title, List<pw.Widget> children) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _rule, width: 0.8),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [_label(title), pw.SizedBox(height: 4), ...children],
            ),
          ),
        );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        box('Bill To', [
          pw.Text(_str(inv['customer_name'], '—'),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          if (_str(inv['customer_phone'], '').isNotEmpty)
            pw.Text('Phone: ${_fmtPhone(inv['customer_phone'].toString())}',
                style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
        ]),
        pw.SizedBox(width: 12),
        box('Vehicle', [
          pw.Text(_str(inv['vehicle_number'], '—').toUpperCase(),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          if (vehicleDesc.isNotEmpty)
            pw.Text(vehicleDesc, style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
          if (km > 0)
            pw.Text('Odometer: ${NumberFormat.decimalPattern('en_IN').format(km)} km',
                style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
        ]),
        pw.SizedBox(width: 12),
        box('Job', [
          pw.Text(_serviceLabel(inv['service_type']?.toString()),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.Text('Received: ${_fmtDate(inv['job_created_at'])}',
              style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
          if (inv['job_completed_at'] != null)
            pw.Text('Completed: ${_fmtDate(inv['job_completed_at'])}',
                style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
        ]),
      ],
    );
  }

  static pw.Widget _itemsTable(List<_Item> items) {
    const head = pw.TextStyle(fontSize: 9, color: PdfColors.white);
    const cell = pw.TextStyle(fontSize: 9.5, color: _ink);

    pw.Widget c(String text, {pw.TextStyle style = cell, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(text, style: style, textAlign: align),
        );

    return pw.Table(
      columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(36),
        3: pw.FixedColumnWidth(78),
        4: pw.FixedColumnWidth(84),
      },
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _rule, width: 0.6),
        bottom: pw.BorderSide(color: _rule, width: 0.8),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _brand),
          children: [
            c('#', style: head),
            c('Description', style: head),
            c('Qty', style: head, align: pw.TextAlign.right),
            c('Rate', style: head, align: pw.TextAlign.right),
            c('Amount', style: head, align: pw.TextAlign.right),
          ],
        ),
        for (var i = 0; i < items.length; i++)
          pw.TableRow(
            decoration: i.isOdd ? const pw.BoxDecoration(color: _band) : null,
            children: [
              c('${i + 1}'),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(items[i].description, style: cell),
                    if (items[i].detail != null)
                      pw.Text(items[i].detail!, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
                  ],
                ),
              ),
              c('${items[i].qty}', align: pw.TextAlign.right),
              c(_money.format(items[i].rate), align: pw.TextAlign.right),
              c(_money.format(items[i].amount), align: pw.TextAlign.right),
            ],
          ),
        if (items.isEmpty)
          pw.TableRow(children: [
            c(''),
            c('No chargeable items', style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
            c(''), c(''), c(''),
          ]),
      ],
    );
  }

  static pw.Widget _totals({
    required double subTotal,
    required double gstPct,
    required double gst,
    required double discount,
    required double total,
    required bool splitGst,
  }) {
    pw.Widget row(String label, String value, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: strong ? 11.5 : 9.5,
                      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: strong ? _ink : _muted)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: strong ? 11.5 : 9.5,
                      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: _ink)),
            ],
          ),
        );

    // Intra-state supply: GST splits equally into CGST + SGST. The halves are
    // derived from the stored GST amount so they always sum to it exactly.
    final cgst = (gst / 2 * 100).roundToDouble() / 100;
    final sgst = gst - cgst;
    final half = _pct(gstPct / 2);

    return pw.Column(children: [
      row('Subtotal', _money.format(subTotal)),
      if (splitGst) ...[
        row('CGST @ $half%', _money.format(cgst)),
        row('SGST @ $half%', _money.format(sgst)),
      ] else
        row('GST @ ${_pct(gstPct)}%', _money.format(gst)),
      if (discount > 0) row('Less: Discount', '− ${_money.format(discount)}'),
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: _band,
        child: row('Grand Total', _money.format(total), strong: true),
      ),
    ]);
  }

  static pw.Widget _signOff(String garageName) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Thank you for your business!',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                pw.SizedBox(height: 2),
                pw.Text('This is a computer-generated invoice.',
                    style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('For $garageName', style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
              pw.SizedBox(height: 32),
              pw.Container(width: 140, height: 0.8, color: _ink),
              pw.SizedBox(height: 3),
              pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ],
      );

  // ── Line items ───────────────────────────────────────────────────────────

  static List<_Item> _lineItems({
    required String service,
    required double labour,
    required double parts,
    required List<Map> tyres,
    required List<String> partsUsed,
  }) {
    final items = <_Item>[];
    if (labour > 0) {
      items.add(_Item('$service — labour / service charges', 1, labour));
    }

    final tyreItems = <_Item>[];
    for (final t in tyres) {
      final qty   = int.tryParse(t['quantity']?.toString() ?? '') ?? 0;
      final price = _num(t['price']);
      if (qty <= 0 || price <= 0) continue;
      final name = [t['brand'], t['model'], t['pattern'], t['size']]
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .join(' ');
      tyreItems.add(_Item('Tyre — $name', qty, price));
    }
    final tyreSum = tyreItems.fold<double>(0, (s, i) => s + i.amount);
    final partsDetail = partsUsed.isEmpty ? null : partsUsed.join('; ');

    if (tyreItems.isNotEmpty && tyreSum <= parts + 0.005) {
      items.addAll(tyreItems);
      final rest = parts - tyreSum;
      if (rest > 0.005) {
        items.add(_Item('Other parts & consumables', 1, rest, detail: partsDetail));
      }
    } else if (parts > 0) {
      // Parts charge was set by hand and doesn't match the tyre log — show it
      // as one line, naming what was fitted, so the total still reconciles.
      final fitted = tyreItems.map((i) => '${i.description.replaceFirst('Tyre — ', '')} ×${i.qty}');
      final detail = [...fitted, ...partsUsed].join('; ');
      items.add(_Item('Parts & materials', 1, parts, detail: detail.isEmpty ? null : detail));
    }
    return items;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static pw.Widget _label(String text) => pw.Text(text.toUpperCase(),
      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _muted, letterSpacing: 0.8));

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text('$k:  ', style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
          pw.Text(v, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink)),
        ]),
      );

  static double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  static String _str(dynamic v, String fallback) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? fallback : s;
  }

  /// Customer phones are stored with the country code (919876543210).
  static String _fmtPhone(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 12 && d.startsWith('91')) {
      return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
    }
    if (d.length == 10) return '${d.substring(0, 5)} ${d.substring(5)}';
    return raw;
  }

  static String _pct(double p) =>
      p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1);

  static String _fmtDate(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '');
    return d == null ? '—' : _date.format(d.toLocal());
  }

  static String _serviceLabel(String? st) {
    if (st == null || st.isEmpty) return 'Service';
    return st
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String? _paymentLabel(dynamic method) {
    switch (method?.toString()) {
      case 'cash':        return 'Cash';
      case 'upi':         return 'UPI';
      case 'card':        return 'Card';
      case 'net_banking': return 'Net Banking';
      default:            return null;
    }
  }

  /// Indian-system words, e.g. 123456.5 → "Rupees One Lakh Twenty Three
  /// Thousand Four Hundred Fifty Six and Fifty Paise Only".
  static String _amountInWords(double amount) {
    final totalPaise = (amount * 100).round();
    final rupees = totalPaise ~/ 100;
    final paise  = totalPaise % 100;
    final r = rupees == 0 ? 'Zero' : _words(rupees);
    final p = paise == 0 ? '' : ' and ${_words(paise)} Paise';
    return 'Rupees $r$p Only';
  }

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
    'Eighteen', 'Nineteen',
  ];
  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety',
  ];

  static String _words(int n) {
    String below100(int x) =>
        x < 20 ? _ones[x] : '${_tens[x ~/ 10]}${x % 10 > 0 ? ' ${_ones[x % 10]}' : ''}';
    String below1000(int x) {
      final h = x ~/ 100, r = x % 100;
      return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) below100(r)].join(' ');
    }

    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;
    if (crore > 0) parts.add('${_words(crore)} Crore');
    if (lakh > 0) parts.add('${below100(lakh)} Lakh');
    if (thousand > 0) parts.add('${below100(thousand)} Thousand');
    if (n > 0) parts.add(below1000(n));
    return parts.join(' ');
  }
}

class _Item {
  _Item(this.description, this.qty, this.rate, {this.detail});
  final String description;
  final int qty;
  final double rate;
  final String? detail;
  double get amount => qty * rate;
}
