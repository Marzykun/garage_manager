import 'package:flutter_test/flutter_test.dart';
import 'package:garage_manager/services/invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final base = {
    'invoice_no': 7,
    'created_at': '2026-10-14T10:00:00Z',
    'customer_name': 'Ravi Kumar',
    'customer_phone': '919876543210',
    'vehicle_number': 'ka01ab1234',
    'brand': 'Maruti',
    'model': 'Swift',
    'service_type': 'wheel_alignment',
    'labour_charge': '0',
    'parts_charge': '5938',
    'gst_percent': '18',
    'discount': '0',
  };
  final garage = {'garage_name': 'Sundar Tyre Agencies', 'address': 'Main Rd', 'phone': '9999999999', 'gstin': '29ABCDE1234F1Z5'};

  test('tyre totals: 5938 -> 534.42 + 534.42, total 7007', () {
    final t = InvoicePdf.tyreTotals(labour: 0, parts: 5938, discount: 0, gstPercent: 18);
    expect(t.cgst, 534.42);
    expect(t.sgst, 534.42);
    expect(t.total, 7007);
    expect(t.roundOff, 0.16);
    final l = InvoicePdf.tyreTotals(labour: 500, parts: 5938, discount: 0, gstPercent: 18);
    expect(l.total, 7507); // labour carries no GST
  });

  test('tyre bill at 12% -> 6% + 6%', () {
    final t = InvoicePdf.tyreTotals(labour: 300, parts: 4400, discount: 0, gstPercent: 12);
    expect(t.cgst, 264);
    expect(t.sgst, 264);
    expect(t.total, 5228);
  });

  test('service bill at 18% on labour 1000 -> 90 + 90, total 1180', () {
    expect(InvoicePdf.serviceGstHalf(labour: 1000, parts: 0, gstPercent: 18), 90);
    expect(InvoicePdf.serviceTotal(labour: 1000, parts: 0, discount: 0, gstPercent: 18), 1180);
  });

  test('service total has no GST', () {
    expect(InvoicePdf.serviceTotal(labour: 800, parts: 200, discount: 50), 950);
  });

  test('part lines: priced only, amounts add up', () {
    final l = InvoicePdf.pricedPartLines([
      {'name': 'Engine Oil', 'quantity': 2, 'unit_price': '450.00'},
      {'name': 'Free item', 'quantity': 1, 'unit_price': '0.00'},
    ]);
    expect(l.length, 1);
    expect(l.first.amount, 900);
  });

  test('builds tyre and service PDFs with part lines', () async {
    final lines = [
      {'name': 'Engine Oil', 'quantity': 2, 'unit_price': '450.00'},
      {'name': 'Oil filter', 'quantity': 1, 'unit_price': '150.00'},
    ];
    // parts 1100 = 1050 itemised + 50 remainder; second case parts too small -> lump fallback
    for (final parts in ['1100', '500']) {
      final t = await InvoicePdf.build({
        'bill_type': 'tyre',
        'invoice': {...base, 'parts_charge': parts},
        'garage': garage,
        'tyres': [],
        'parts_lines': lines,
        'parts_used': [],
      });
      expect(t.length, greaterThan(1000));
      final s = await InvoicePdf.build({
        'bill_type': 'service',
        'invoice': {...base, 'labour_charge': '800', 'parts_charge': parts, 'gst_percent': '18'},
        'garage': garage,
        'tyres': [],
        'parts_lines': lines,
        'parts_used': [],
      });
      expect(s.length, greaterThan(1000));
    }
  });

  test('tyre bill with a tyre line and a non-tyre part line builds', () async {
    final t = await InvoicePdf.build({
      'bill_type': 'tyre',
      'invoice': {...base, 'parts_charge': '6888'}, // 2 x 2969 + 950
      'garage': garage,
      'tyres': [
        {'brand': 'CEAT', 'model': 'Milaze', 'pattern': 'Sport', 'size': '145/80R12', 'price': 2969, 'quantity': 2},
      ],
      'parts_lines': [
        {'name': 'engine oil', 'quantity': 1, 'unit_price': '950.00'},
      ],
      'parts_used': [],
    });
    expect(t.length, greaterThan(1000));
  });

  test('builds tyre and service PDFs', () async {
    final tyre = await InvoicePdf.build({
      'bill_type': 'tyre',
      'invoice': base,
      'garage': garage,
      'tyres': [
        {'brand': 'MRF', 'model': 'ZLX', 'pattern': 'Tubeless', 'size': '185/65R15', 'price': 2969, 'quantity': 2},
      ],
      'parts_used': [],
    });
    expect(tyre.length, greaterThan(1000));
    final service = await InvoicePdf.build({
      'bill_type': 'service',
      'invoice': {...base, 'labour_charge': '800', 'parts_charge': '0', 'gst_percent': '0'},
      'garage': garage,
      'tyres': [],
      'parts_used': [],
    });
    expect(service.length, greaterThan(1000));
    final gstService = await InvoicePdf.build({
      'bill_type': 'service',
      'invoice': {...base, 'labour_charge': '1000', 'parts_charge': '0', 'gst_percent': '18'},
      'garage': garage,
      'tyres': [],
      'parts_used': [],
    });
    expect(gstService.length, greaterThan(1000));
  });
}
