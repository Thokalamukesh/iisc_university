import 'dart:async';

import 'package:api_selfxo_project/api/kiosk_api.dart';
import 'package:api_selfxo_project/core/device_layout.dart';
import 'package:api_selfxo_project/core/idle_timer.dart';
import 'package:api_selfxo_project/core/kiosk_memory_service.dart';
import 'package:api_selfxo_project/screens/admin_dashboard_screens/adim_homescreen.dart';
import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:api_selfxo_project/screens/main_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Post-payment order token screen: shows pickup QR from [KioskApi.getOrderDetails].
class OrderPickupConfirmationScreen extends StatefulWidget {
  final int orderId;
  final String? restaurantName;
  final String? orderType;

  const OrderPickupConfirmationScreen({
    super.key,
    required this.orderId,
    this.restaurantName,
    this.orderType,
  });

  @override
  State<OrderPickupConfirmationScreen> createState() =>
      _OrderPickupConfirmationScreenState();
}

class _OrderPickupConfirmationScreenState
    extends State<OrderPickupConfirmationScreen> {
  static const Color _brand = Color(0xFF9F342C);
  static const Color _canvas = Color(0xFFF6F1EA);
  static const Duration _autoReturnTimeout = Duration(minutes: 2);

  bool _loading = true;
  String? _loadError;
  String _pickupCode = '';
  String _orderNumberLabel = '';
  String _paymentStatus = '';
  String _restaurantName = '';
  Duration _remaining = _autoReturnTimeout;
  Timer? _autoReturnTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    IdleTimer.pause();
    KioskMemoryService.instance.pause();
    _restaurantName = widget.restaurantName?.trim() ?? '';
    _startAutoReturnTimers();
    unawaited(_loadOrderDetails());
  }

  @override
  void dispose() {
    _autoReturnTimer?.cancel();
    _countdownTimer?.cancel();
    IdleTimer.resume();
    KioskMemoryService.instance.resume();
    super.dispose();
  }

  void _startAutoReturnTimers() {
    _autoReturnTimer?.cancel();
    _countdownTimer?.cancel();
    _remaining = _autoReturnTimeout;
    _autoReturnTimer = Timer(_autoReturnTimeout, _navigateHome);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final next = _remaining - const Duration(seconds: 1);
        _remaining = next.isNegative ? Duration.zero : next;
      });
    });
  }

  Future<void> _loadOrderDetails() async {
    try {
      final res = await KioskApi().getOrderDetails(widget.orderId);
      final parsed = _parsePickupInfo(res.data, widget.orderId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = null;
        _pickupCode = parsed.pickupCode;
        _orderNumberLabel = parsed.orderNumberLabel;
        _paymentStatus = parsed.paymentStatus;
        if (parsed.restaurantName != null &&
            parsed.restaurantName!.trim().isNotEmpty) {
          _restaurantName = parsed.restaurantName!.trim();
        }
      });
    } catch (e) {
      if (!mounted) return;
      final fallback = _fallbackPickupInfo(widget.orderId);
      setState(() {
        _loading = false;
        _loadError = 'Could not refresh order details. Showing order token.';
        _pickupCode = fallback.pickupCode;
        _orderNumberLabel = fallback.orderNumberLabel;
        _paymentStatus = fallback.paymentStatus;
      });
    }
  }

  void _navigateHome() {
    if (!mounted) return;
    final Widget home;
    if (kIsWeb) {
      home = const CustomerBlockScreen();
    } else if (isTabletContext(context)) {
      home = const AdminHomeScreen();
    } else {
      final safeOrderType =
          widget.orderType?.trim().isEmpty ?? true ? 'dine_in' : widget.orderType!;
      home = MainNavigation(orderType: safeOrderType);
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => home),
      (_) => false,
    );
  }

  String _formatRemaining(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720;
    final qrSize = compact ? 220.0 : 280.0;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop || !mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Use Done to continue'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: kIsWeb ? _canvas : const Color(0xFF0E1220),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 22 : 32,
                    vertical: compact ? 24 : 32,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F7EE),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF16A34A),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Payment successful',
                              style: TextStyle(
                                fontSize: compact ? 22 : 26,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1D1D1D),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Show this order QR at pickup or counter',
                        style: TextStyle(
                          fontSize: compact ? 14 : 15,
                          height: 1.45,
                          color: Colors.black.withOpacity(0.62),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_restaurantName.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _restaurantName.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _brand,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_loadError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFED7AA)),
                            ),
                            child: Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF9A3412),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBF7),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFEADCCD)),
                            ),
                            child: QrImageView(
                              data: _pickupCode,
                              size: qrSize,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          _pickupCode,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 18 : 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            color: const Color(0xFF1D1D1D),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _infoRow(
                          label: 'Order number',
                          value: _orderNumberLabel,
                          compact: compact,
                        ),
                        const SizedBox(height: 8),
                        _infoRow(
                          label: 'Payment status',
                          value: _paymentStatus.isEmpty ? 'Paid' : _paymentStatus,
                          compact: compact,
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'Auto return in ${_formatRemaining(_remaining)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.black.withOpacity(0.45),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _loading ? null : _navigateHome,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow({
    required String label,
    required String value,
    required bool compact,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickupInfo {
  final String pickupCode;
  final String orderNumberLabel;
  final String paymentStatus;
  final String? restaurantName;

  const _PickupInfo({
    required this.pickupCode,
    required this.orderNumberLabel,
    required this.paymentStatus,
    this.restaurantName,
  });
}

_PickupInfo _fallbackPickupInfo(int orderId) {
  return _PickupInfo(
    pickupCode: 'PRINT_ORDER_$orderId',
    orderNumberLabel: '#$orderId',
    paymentStatus: 'Paid',
  );
}

_PickupInfo _parsePickupInfo(dynamic data, int orderId) {
  if (data is! Map) return _fallbackPickupInfo(orderId);

  final map = data.map((k, v) => MapEntry('$k', v));
  final orderNode = map['order'] ?? map['orderDetails'];
  final orderMap = orderNode is Map
      ? orderNode.map((k, v) => MapEntry('$k', v))
      : null;

  String? readString(List<String> keys, [Map<String, dynamic>? from]) {
    for (final source in [from, map]) {
      if (source == null) continue;
      for (final key in keys) {
        final value = source[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString().trim();
        }
      }
    }
    return null;
  }

  final pickupCode = readString(
        ['pickup_code', 'pickupCode', 'token', 'order_token'],
        orderMap,
      ) ??
      readString(['pickup_code', 'pickupCode']) ??
      readString(
        [
          'formatted_order_number',
          'show_formatted_order_number',
          'formattedOrderNumber',
        ],
        orderMap,
      ) ??
      readString([
        'formatted_order_number',
        'show_formatted_order_number',
      ]);

  final orderNumberLabel = readString(
        [
          'formatted_order_number',
          'show_formatted_order_number',
          'order_number',
          'display_order_number',
        ],
        orderMap,
      ) ??
      readString([
        'formatted_order_number',
        'order_number',
      ]) ??
      '#$orderId';

  final paymentStatus = readString(
        ['payment_status', 'paymentStatus', 'status'],
        orderMap,
      ) ??
      readString(['payment_status', 'paymentStatus']) ??
      'Paid';

  final restaurantName = readString(
    ['restaurant_name', 'restaurantName'],
  );

  return _PickupInfo(
    pickupCode: pickupCode ?? _fallbackPickupInfo(orderId).pickupCode,
    orderNumberLabel: orderNumberLabel,
    paymentStatus: paymentStatus,
    restaurantName: restaurantName,
  );
}
