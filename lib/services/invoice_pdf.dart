import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a printable A4 bill from the `/api/invoices/:id/print` payload:
/// `{ bill_type: 'tyre'|'service', invoice, garage, tyres, parts_used }`.
/// Tyre bill = "Cash Bill" (CGST + SGST, each half the stored gst_percent, on
/// parts only, rounded total); service bill = "LABOUR BILL" (GST, if any, on
/// labour + parts, shown as CGST/SGST lines).
class InvoicePdf {
  static const _ink     = PdfColor.fromInt(0xFF1A2332);
  static const _muted   = PdfColor.fromInt(0xFF5A6578);

  static final _date  = DateFormat('dd MMM yyyy');

  static String invoiceNumber(Map<String, dynamic> invoice) {
    final n = invoice['invoice_no'];
    return n == null ? '—' : 'INV-${n.toString().padLeft(4, '0')}';
  }

  static const _tyreTagline =
      'Computerised 3D Wheel Alignment & Balancing, Automatic Tyre Changing, Tubeless Tyre Repair, Nitrogen Air, Water Wash';
  static const _serviceTagline =
      'Computerised 3D Wheel Alignment, Wheel balancing, Tyre changing, Nitrogen air, Car washing, Interior cleaning, Exterior polishing';

  static Future<Uint8List> build(Map<String, dynamic> data) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold    = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));

    final inv    = (data['invoice'] as Map).cast<String, dynamic>();
    final garage = (data['garage']  as Map? ?? {}).cast<String, dynamic>();
    final tyres  = (data['tyres']   as List? ?? []).cast<Map>();
    final partsUsed = (data['parts_used'] as List? ?? []).map((e) => e.toString()).toList();
    final partLines = pricedPartLines(data['parts_lines'] as List? ?? []);
    final isTyre = (data['bill_type'] ?? (tyres.isNotEmpty ? 'tyre' : 'service')) == 'tyre';
    final garageName = _str(garage['garage_name'], 'My Garage');

    final doc = pw.Document(
      title: '${invoiceNumber(inv)} — $garageName',
      author: garageName,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        build: (ctx) => isTyre
            ? _tyreBill(inv, garage, garageName, tyres, partsUsed, partLines)
            : _serviceBill(inv, garage, garageName, partsUsed, partLines),
      ),
    );
    return doc.save();
  }

  /// Inventory part lines from the print payload's `parts_lines` that carry a
  /// price: `(name, qty, amount)`. Unpriced lines add nothing so they are left out.
  static List<({String name, int qty, double amount})> pricedPartLines(List raw) => [
        for (final p in raw.cast<Map>())
          if ((int.tryParse(p['quantity']?.toString() ?? '') ?? 0) > 0 && _num(p['unit_price']) > 0)
            (
              name: _str(p['name'], 'Part'),
              qty: int.parse(p['quantity'].toString()),
              amount: _num(p['unit_price']) * int.parse(p['quantity'].toString()),
            )
      ];

  // ── Tyre sales bill ("Cash Bill") ────────────────────────────────────────

  static List<pw.Widget> _tyreBill(Map<String, dynamic> inv, Map<String, dynamic> garage,
      String garageName, List<Map> tyres, List<String> partsUsed,
      List<({String name, int qty, double amount})> partLines) {
    final labour   = _num(inv['labour_charge']);
    final parts    = _num(inv['parts_charge']);
    final discount = _num(inv['discount']);
    final pct      = _num(inv['gst_percent']);
    final t = tyreTotals(labour: labour, parts: parts, discount: discount, gstPercent: pct);

    // Rows: [particulars, size, qty, amount]
    final rows = <List<String>>[];
    double tyreSum = 0;
    final tyreRows = <List<String>>[];
    for (final y in tyres) {
      final qty = int.tryParse(y['quantity']?.toString() ?? '') ?? 0;
      final price = _num(y['price']);
      if (qty <= 0 || price <= 0) continue;
      tyreSum += qty * price;
      tyreRows.add([
        [y['brand'], y['model'], y['pattern']]
            .where((e) => e != null && e.toString().trim().isNotEmpty)
            .join(' '),
        _str(y['size'], ''),
        '$qty',
        _money2(qty * price),
      ]);
    }
    // Inventory parts: name in Particulars, qty in the Tyre/qty column
    final partRows = [for (final l in partLines) [l.name, '', '${l.qty}', _money2(l.amount)]];
    final partSum = partLines.fold<double>(0, (a, l) => a + l.amount);
    final itemised = tyreSum + partSum;
    if ((tyreRows.isNotEmpty || partRows.isNotEmpty) && itemised <= parts + 0.005) {
      rows.addAll(tyreRows);
      rows.addAll(partRows);
      if (parts - itemised > 0.005) rows.add(['Other parts & consumables', '', '', _money2(parts - itemised)]);
    } else if (parts > 0) {
      // Parts charge was set by hand and doesn't match the tyre log.
      final fitted = [...tyreRows, ...partRows].map((r) => '${r[0]} ${r[1]} x${r[2]}'.trim());
      final detail = [...fitted, ...partsUsed].join('; ');
      rows.add(['Parts & materials${detail.isEmpty ? '' : ' ($detail)'}', '', '', _money2(parts)]);
    }
    if (labour > 0) {
      rows.add(['${_serviceLabel(inv['service_type']?.toString())} — labour (no GST)', '', '', _money2(labour)]);
    }

    const head = pw.TextStyle(fontSize: 9, color: _ink, fontWeight: pw.FontWeight.bold);
    const cell = pw.TextStyle(fontSize: 9.5, color: _ink);
    pw.Widget c(String x, {pw.TextStyle style = cell, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Text(x, style: style, textAlign: align),
        );
    // Amount as two cells: Rs | Ps, split from a "1234.56" string.
    List<pw.Widget> amt(String m, {pw.TextStyle style = cell}) {
      final p = m.split('.');
      return [c(p[0], style: style, align: pw.TextAlign.right), c(p[1], style: style)];
    }

    pw.TableRow sum(String label, double v, {pw.TextStyle style = cell}) => pw.TableRow(children: [
          c(''), c(label, style: style), c(''), c(''), c(''), ...amt(_money2(v), style: style),
        ]);

    const minRows = 8;
    final table = pw.Table(
      border: pw.TableBorder.all(color: _ink, width: 0.7),
      columnWidths: const {
        0: pw.FixedColumnWidth(30),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(64),
        3: pw.FixedColumnWidth(40),
        4: pw.FixedColumnWidth(40),
        5: pw.FixedColumnWidth(62),
        6: pw.FixedColumnWidth(30),
      },
      children: [
        pw.TableRow(children: [
          c('S.No', style: head),
          c('Particulars', style: head),
          c('Size', style: head),
          c('Tyre', style: head, align: pw.TextAlign.center),
          c('Tube', style: head, align: pw.TextAlign.center),
          c('Amount Rs.', style: head, align: pw.TextAlign.right),
          c('Ps.', style: head),
        ]),
        for (var i = 0; i < rows.length || i < minRows; i++)
          pw.TableRow(
              children: i < rows.length
                  ? [
                      c('${i + 1}'),
                      c(rows[i][0]),
                      c(rows[i][1]),
                      c(rows[i][2], align: pw.TextAlign.center),
                      c(''),
                      ...amt(rows[i][3]),
                    ]
                  : [c(' '), c(''), c(''), c(''), c(''), c(''), c('')]),
        sum('Amount', t.parts + labour),
        if (pct > 0) sum('CGST ${_pct(pct / 2)}% (on parts)', t.cgst),
        if (pct > 0) sum('SGST ${_pct(pct / 2)}% (on parts)', t.sgst),
        if (discount > 0) sum('Less: Discount', -discount),
        sum('Round Off', t.roundOff),
        sum('Total Rs.', t.total, style: head),
      ],
    );

    return [
      _paperHeader(garage, garageName, _tyreTagline),
      pw.SizedBox(height: 6),
      pw.Center(
          child: pw.Text('Cash Bill',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink))),
      pw.SizedBox(height: 8),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _kv('Invoice No', invoiceNumber(inv)),
        _kv('Date', _fmtDate(inv['created_at'])),
      ]),
      pw.SizedBox(height: 4),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: _kv('To', _toLine(inv))),
        _kv('Vehicle No', _str(inv['vehicle_number'], '—').toUpperCase()),
      ]),
      pw.SizedBox(height: 8),
      table,
      pw.SizedBox(height: 8),
      pw.Text('Amount in words (Rupees): ${_amountInWords(t.total)}',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 28),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Expanded(
          child: pw.Text(
            'Goods sold are covered against manufacturing defects as per the manufacturer\'s warranty.\n'
            'Claims are subject to local jurisdiction.\n'
            'Goods once sold will not be taken back.',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Column(children: [
          pw.Text('For $garageName',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 34),
          pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        ]),
      ]),
    ];
  }

  /// Totals of a tyre bill, in rupees (each figure rounded to paise). GST
  /// applies to [parts] only (half as CGST, half as SGST); [labour] is added
  /// without GST; the total is rounded to the nearest rupee.
  static ({double parts, double cgst, double sgst, double roundOff, double total}) tyreTotals({
    required double labour,
    required double parts,
    required double discount,
    required double gstPercent,
  }) {
    double r2(double v) => (v * 100).round() / 100;
    final half = r2(parts * gstPercent / 200);
    final raw = r2(labour + parts + half * 2 - discount);
    final total = raw.roundToDouble();
    return (parts: parts, cgst: half, sgst: half, roundOff: r2(total - raw), total: total);
  }

  // ── Service bill ("LABOUR BILL") ─────────────────────────────────────────

  static List<pw.Widget> _serviceBill(Map<String, dynamic> inv, Map<String, dynamic> garage,
      String garageName, List<String> partsUsed,
      List<({String name, int qty, double amount})> partLines) {
    final labour   = _num(inv['labour_charge']);
    final parts    = _num(inv['parts_charge']);
    final discount = _num(inv['discount']);
    final pct   = _num(inv['gst_percent']);
    final half  = serviceGstHalf(labour: labour, parts: parts, gstPercent: pct);
    final total = serviceTotal(labour: labour, parts: parts, discount: discount, gstPercent: pct);

    final rows = <List<String>>[
      if (labour > 0) [_serviceLabel(inv['service_type']?.toString()), '1', _money2(labour)],
      ..._servicePartRows(parts, partsUsed, partLines),
    ];
    const head = pw.TextStyle(fontSize: 9.5, color: _ink, fontWeight: pw.FontWeight.bold);
    const cell = pw.TextStyle(fontSize: 10, color: _ink);
    pw.Widget c(String x, {pw.TextStyle style = cell, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(x, style: style, textAlign: align),
        );
    final model = [inv['brand'], inv['model']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' ');

    return [
      _paperHeader(garage, garageName, _serviceTagline),
      pw.SizedBox(height: 6),
      pw.Center(
          child: pw.Text('LABOUR BILL',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink))),
      pw.SizedBox(height: 8),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        _kv('No.', invoiceNumber(inv)),
        _kv('Date', _fmtDate(inv['created_at'])),
      ]),
      pw.SizedBox(height: 4),
      _kv('To', _toLine(inv)),
      pw.SizedBox(height: 4),
      pw.Row(children: [
        _kv('Veh.No', _str(inv['vehicle_number'], '—').toUpperCase()),
        pw.SizedBox(width: 30),
        _kv('Model', model.isEmpty ? '—' : model),
      ]),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: _ink, width: 0.7),
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.FixedColumnWidth(50),
          2: pw.FixedColumnWidth(90),
        },
        children: [
          pw.TableRow(children: [
            c('Nature of Works', style: head),
            c('Qty', style: head, align: pw.TextAlign.center),
            c('Amount', style: head, align: pw.TextAlign.right),
          ]),
          for (var i = 0; i < rows.length || i < 6; i++)
            pw.TableRow(
                children: i < rows.length
                    ? [
                        c(rows[i][0]),
                        c(rows[i][1], align: pw.TextAlign.center),
                        c(rows[i][2], align: pw.TextAlign.right),
                      ]
                    : [c(' '), c(''), c('')]),
          if (discount > 0)
            pw.TableRow(children: [
              c('Less: Discount'), c(''), c('-${_money2(discount)}', align: pw.TextAlign.right)]),
          if (half > 0) ...[
            pw.TableRow(children: [
              c('CGST ${_pct(pct / 2)}%'), c(''), c(_money2(half), align: pw.TextAlign.right)]),
            pw.TableRow(children: [
              c('SGST ${_pct(pct / 2)}%'), c(''), c(_money2(half), align: pw.TextAlign.right)]),
          ],
          pw.TableRow(children: [
            c('Total', style: head), c(''), c(_money2(total), style: head, align: pw.TextAlign.right)]),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text('Rupees in words: ${_amountInWords(total)}',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 28),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Column(children: [
          pw.Text('For $garageName',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 34),
          pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        ]),
      ),
    ];
  }

  /// Parts rows of a service bill: itemised lines (+ remainder) when they fit
  /// inside the parts charge, otherwise one lump row as before.
  static List<List<String>> _servicePartRows(
      double parts, List<String> partsUsed, List<({String name, int qty, double amount})> lines) {
    if (parts <= 0) return [];
    final sum = lines.fold<double>(0, (a, l) => a + l.amount);
    if (lines.isNotEmpty && sum <= parts + 0.005) {
      return [
        for (final l in lines) [l.name, '${l.qty}', _money2(l.amount)],
        if (parts - sum > 0.005) ['Other parts & consumables', '1', _money2(parts - sum)],
      ];
    }
    return [[partsUsed.isEmpty ? 'Parts & materials' : 'Parts: ${partsUsed.join('; ')}', '1', _money2(parts)]];
  }

  /// Half of the GST (the CGST or SGST figure) on a service bill: GST applies to labour + parts.
  static double serviceGstHalf({required double labour, required double parts, required double gstPercent}) =>
      ((labour + parts) * gstPercent / 200 * 100).round() / 100;

  static double serviceTotal({
    required double labour,
    required double parts,
    required double discount,
    double gstPercent = 0,
  }) =>
      ((labour + parts + 2 * serviceGstHalf(labour: labour, parts: parts, gstPercent: gstPercent) - discount) * 100)
          .round() /
      100;

  // ── Shared pieces ────────────────────────────────────────────────────────

  static pw.Widget _paperHeader(Map<String, dynamic> garage, String name, String tagline) {
    final address = _str(garage['address'], '');
    final phone   = _str(garage['phone'], '');
    final gstin   = _str(garage['gstin'], '');
    pw.Widget line(String t, {double size = 9, bool b = false}) => pw.Text(t,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
            fontSize: size, color: _ink, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal));
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.5))),
      width: double.infinity,
      child: pw.Column(children: [
        line(name, size: 20, b: true),
        pw.SizedBox(height: 3),
        line(tagline, size: 8.5),
        if (address.isNotEmpty) line(address),
        if (phone.isNotEmpty) line('Phone: $phone'),
        if (gstin.isNotEmpty) line('GSTIN: $gstin', b: true),
      ]),
    );
  }

  static String _toLine(Map<String, dynamic> inv) {
    final phone = _str(inv['customer_phone'], '');
    return '${_str(inv['customer_name'], '—')}${phone.isEmpty ? '' : '  (${_fmtPhone(phone)})'}';
  }

  static String _money2(double v) => v.toStringAsFixed(2);

  // ── Helpers ──────────────────────────────────────────────────────────────

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
