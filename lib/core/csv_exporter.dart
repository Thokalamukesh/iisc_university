import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CsvExporter {
  static Future<void> export(List orders) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/billing.csv");

    final buffer = StringBuffer();
    buffer.writeln("Order ID,Status,Total");

    for (final o in orders) {
      buffer.writeln("${o["id"]},${o["status"]},${o["total"]}");
    }

    await file.writeAsString(buffer.toString());
  }
}
