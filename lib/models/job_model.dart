class Job {
  final String id;
  final String vehicleReg;
  final String customerName;
  final String? phone;
  final List<String> services;
  final String status;

  Job({
    required this.id,
    required this.vehicleReg,
    required this.customerName,
    this.phone,
    required this.services,
    required this.status,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    final services = <String>[];
    final rawServices = json['services'];
    if (rawServices is List) {
      services.addAll(rawServices.map((item) => item.toString()));
    } else if (rawServices is String) {
      services.addAll(
        rawServices
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
    }

    return Job(
      id: json['id']?.toString() ?? json['jobId']?.toString() ?? '',
      vehicleReg:
          json['vehicleReg']?.toString() ?? json['vehicle']?.toString() ?? '',
      customerName:
          json['customerName']?.toString() ??
          json['customer']?.toString() ??
          '',
      phone: json['phone']?.toString() ?? json['customerPhone']?.toString(),
      services: services,
      status: json['status']?.toString() ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vehicleReg': vehicleReg,
      'customerName': customerName,
      'phone': phone,
      'services': services,
      'status': status,
    };
  }
}
