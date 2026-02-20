import 'package:intl/intl.dart';

class AnalyticsUtils {
  /// 🔹 DAILY REVENUE (FOR CHART)
  static Map<String, double> dailyRevenue(List orders) {
    final Map<String, double> result = {};

    for (final o in orders) {
      if (o["status"] != "paid") continue;

      final date = DateFormat(
        "yyyy-MM-dd",
      ).format(DateTime.parse(o["created_at"]));

      final amount = double.tryParse(o["total"].toString()) ?? 0;

      result[date] = (result[date] ?? 0) + amount;
    }

    return result;
  }

  /// 🔹 TAX BREAKDOWN
  static Map<String, double> taxBreakdown(List orders) {
    final Map<String, double> taxes = {};

    for (final o in orders) {
      if (o["status"] != "paid") continue;

      final orderTaxes = o["taxes"] ?? [];

      for (final t in orderTaxes) {
        final taxName = t["tax"]?["tax_name"] ?? "Unknown Tax";
        final taxAmount =
            double.tryParse(t["tax_amount"]?.toString() ?? "0") ?? 0;

        taxes[taxName] = (taxes[taxName] ?? 0) + taxAmount;
      }
    }

    return taxes;
  }
}
