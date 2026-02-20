import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dio_client.dart';

class KioskApi {
  // =========================================================
  // RESTAURANT + KIOSK SETTINGS
  // =========================================================
  Future<Response> getRestaurantData() async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/getRestaurantData");
  }

  // =========================================================
  // PRODUCTS
  // =========================================================
  Future<Response> getProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("auth_token"); // or access_token

    final dio = await DioClient.getAuthedDio();
    final res = await dio.get("kiosks/getProducts");
    return res;
  }

  // =========================================================
  // CREATE ORDER
  // =========================================================
  Future<Response> createOrder({
    required String orderType,
    required List<Map<String, dynamic>> orderItems,
  }) async {
    final dio = await DioClient.getAuthedDio();
    return dio.post(
      "kiosks/createOrder",
      data: {"orderType": orderType, "orderItemList": orderItems},
    );
  }

  // =========================================================
  // GENERATE QR
  // =========================================================
  Future<Response> generateQr({required int orderId}) async {
    final dio = await DioClient.getAuthedDio();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString("device_id");

    return dio.get(
      "kiosks/orders/$orderId/generateQr",
      options: Options(
        headers: {
          if (deviceId != null && deviceId.isNotEmpty) "X-DEVICE-ID": deviceId,
        },
      ),
    );
  }

  // =========================================================
  // CHECK PAYMENT
  // =========================================================
  Future<Response> checkPayment(int orderId) async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/orders/$orderId/checkPayment");
  }

  // =========================================================
  // GET ORDER DETAILS
  // =========================================================
  Future<Response> getOrderDetails(int orderId) async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/orders/$orderId");
  }

  // =========================================================
  // PRINTER (BACKEND + CAPACITOR)
  // =========================================================

  /// 🖨️ Get available printers (Angular + Capacitor side)
  /// Same as EpsonUSBPrinter.getPrinterList()
  Future<List<Map<String, dynamic>>> getPrinterList() async {
    final dio = await DioClient.getAuthedDio();
    final res = await dio.get("kiosks/printers");

    final List list = res.data["printers"] ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// 🖨️ Save selected printer for this kiosk
  /// Same as getSelectedPrinter() logic
  Future<void> saveSelectedPrinter(String productId) async {
    final dio = await DioClient.getAuthedDio();
    await dio.post("kiosks/printers/select", data: {"product_id": productId});
  }

  /// 🖨️ Get already selected printer (optional)
  Future<Map<String, dynamic>?> getSelectedPrinter() async {
    final dio = await DioClient.getAuthedDio();
    final res = await dio.get("kiosks/printers/selected");
    return res.data["printer"];
  }

  // =========================================================
  // DEVICE MONITORING
  // =========================================================

  /// Ping device (used for printer/device status)
  /// GET kiosks/ping/{deviceId}/default
  Future<Response> pingDevice() async {
    final dio = await DioClient.getAuthedDio();
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString("device_id") ?? "default_device";

    return dio.get("kiosks/ping/$deviceId/default");
  }

  // =========================================================
  // PRINT RECEIPT (BACKEND HANDLES PRINTER)
  // =========================================================

  /// 🔥 Print receipt
  /// Angular + Capacitor + Epson handles actual printing
  Future<Response> printReceipt(int orderId) async {
    final dio = await DioClient.getAuthedDio();
    return dio.get("kiosks/orders/printReceipt/$orderId");
  }

  // =========================================================
  // ORDER SUMMARY (CATEGORY SUMMARY)
  // =========================================================

  Future<Response> getOrderSummary({
    required String date,
    int? branchId,
    int? restaurantId,
  }) async {
    final dio = await DioClient.getAuthedDio();
    final params = <String, dynamic>{
      "date": date,
      "from_date": date,
      "to_date": date,
      if (branchId != null) "branch_id": branchId,
      if (restaurantId != null) "restaurant_id": restaurantId,
    };

    try {
      return await dio.post("kiosk/order-summary", data: params);
    } catch (_) {
      return dio.get("kiosk/order-summary", queryParameters: params);
    }
  }
}
