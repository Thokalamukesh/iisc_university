import 'package:shared_preferences/shared_preferences.dart';

class ReceiptPrintMode {
  static const String prefsKey = "receipt_print_mode";

  static Future<String?> getStoredMode() async {
    final prefs = await SharedPreferences.getInstance();
    return normalize(prefs.getString(prefsKey));
  }

  static Future<void> storeFromMap(Map? data) async {
    final mode = fromSettingsMap(data);
    if (mode == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode);
  }

  static String? fromSettingsMap(Map? data) {
    if (data == null) return null;
    final map = data.cast<String, dynamic>();

    const keyedModes = [
      "receipt_print_mode",
      "print_receipt_mode",
      "bill_print_mode",
      "receipt_mode",
      "bill_mode",
      "print_mode",
      "bill_type",
      "receipt_type",
      "print_type",
      "receipt_copy",
      "print_copy",
      "receipt_copies",
      "print_copies",
    ];

    for (final key in keyedModes) {
      if (!map.containsKey(key)) continue;
      final normalized = normalize(map[key]);
      if (normalized != null) return normalized;
    }

    final customerOnly = _readBool(map, const [
      "customer_bill_only",
      "only_customer_bill",
      "customer_only",
      "print_customer_only",
      "customer_copy_only",
    ]);
    if (customerOnly == true) return "customer";

    final counterOnly = _readBool(map, const [
      "counter_bill_only",
      "only_counter_bill",
      "counter_only",
      "print_counter_only",
      "counter_copy_only",
    ]);
    if (counterOnly == true) return "counter";

    final customer = _readBool(map, const [
      "print_customer_bill",
      "customer_bill",
      "customer_copy",
      "print_customer_copy",
      "print_customer_receipt",
    ]);
    final counter = _readBool(map, const [
      "print_counter_bill",
      "counter_bill",
      "counter_copy",
      "print_counter_copy",
      "print_counter_receipt",
    ]);

    if (customer != null || counter != null) {
      if (customer == true && counter == true) return "both";
      if (customer == true && counter != true) return "customer";
      if (counter == true && customer != true) return "counter";
    }

    return null;
  }

  static String? normalize(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final v = value.toInt();
      if (v == 1) return "customer";
      if (v == 2) return "counter";
      if (v == 3) return "both";
      return null;
    }
    if (value is bool) {
      return value ? "both" : null;
    }
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return null;
    if (text == "1") return "customer";
    if (text == "2") return "counter";
    if (text == "3") return "both";
    if (text.contains("both") || text.contains("all")) return "both";
    if (text.contains("customer")) return "customer";
    if (text.contains("counter")) return "counter";
    return null;
  }

  static bool? _readBool(Map data, List<String> keys) {
    for (final key in keys) {
      if (!data.containsKey(key)) continue;
      final raw = data[key];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      if (raw is String) {
        final v = raw.trim().toLowerCase();
        if (v.isEmpty) return null;
        if (v == "1" || v == "true" || v == "yes" || v == "y" || v == "on") {
          return true;
        }
        if (v == "0" ||
            v == "false" ||
            v == "no" ||
            v == "n" ||
            v == "off") {
          return false;
        }
      }
    }
    return null;
  }
}
