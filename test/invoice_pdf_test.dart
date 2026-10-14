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

  test('service total has no GST', () {
    expect(InvoicePdf.serviceTotal(labour: 800, parts: 200, discount: 50), 950);
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
  });
}
