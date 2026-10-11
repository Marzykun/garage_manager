import 'package:flutter/material.dart';

/// Vehicle types offered when creating a job card and as a filter on the
/// Customers screen. `value` is what's stored in vehicles.vehicle_type.
class VehicleType {
  const VehicleType(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;
}

const kVehicleTypes = [
  VehicleType('car',        'Car',        Icons.directions_car_outlined),
  VehicleType('suv',        'SUV',        Icons.airport_shuttle_outlined),
  VehicleType('bike',       'Bike',       Icons.two_wheeler_outlined),
  VehicleType('auto',       'Auto',       Icons.electric_rickshaw_outlined),
  VehicleType('commercial', 'Commercial', Icons.local_shipping_outlined),
];

VehicleType? vehicleTypeFor(String? value) {
  if (value == null) return null;
  for (final t in kVehicleTypes) {
    if (t.value == value.toLowerCase()) return t;
  }
  return null;
}

/// Service (job) types — `value` is the backend's service_type enum.
const kServiceTypes = [
  ('wheel_alignment', 'Wheel Alignment'),
  ('wheel_balancing', 'Wheel Balancing'),
  ('tyre_change',     'Tyre Change'),
  ('water_wash',      'Water Wash'),
  ('full_service',    'Full Service'),
  ('car_wash',        'Car Wash'),
  ('other',           'Other'),
];

String serviceLabel(String? value) {
  for (final s in kServiceTypes) {
    if (s.$1 == value) return s.$2;
  }
  if (value == null || value.isEmpty) return 'Service';
  return value.replaceAll('_', ' ');
}
