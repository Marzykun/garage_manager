class Customer {
  final String name;
  final String phone;
  final String vehicleReg;

  Customer({required this.name, required this.phone, required this.vehicleReg});

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      name: json['name']?.toString() ?? json['customerName']?.toString() ?? '',
      phone:
          json['phone']?.toString() ?? json['customerPhone']?.toString() ?? '',
      vehicleReg:
          json['vehicleReg']?.toString() ?? json['vehicle']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'phone': phone, 'vehicleReg': vehicleReg};
  }
}
