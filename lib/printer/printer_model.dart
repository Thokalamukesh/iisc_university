class PrinterInfo {
  final String productId;
  final String name;

  PrinterInfo({required this.productId, required this.name});

  factory PrinterInfo.fromJson(Map<String, dynamic> json) {
    return PrinterInfo(productId: json['productId'], name: json['name']);
  }
}
