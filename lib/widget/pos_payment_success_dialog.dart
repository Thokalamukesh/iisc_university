import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PosPaymentSuccessData {
  final String orderId;
  final String amountPaid;
  final String amountLabel;
  final String paymentMethod;
  final String dateTimeText;
  final String title;
  final String subtitle;
  final List<String> orderedItems;

  const PosPaymentSuccessData({
    required this.orderId,
    required this.amountPaid,
    this.amountLabel = 'Amount Paid',
    required this.paymentMethod,
    required this.dateTimeText,
    this.title = 'Payment Successful',
    this.subtitle = 'Order Confirmed',
    this.orderedItems = const [],
  });
}

Future<void> showPosPaymentSuccessDialog(
  BuildContext context, {
  required PosPaymentSuccessData data,
  Duration autoClose = const Duration(seconds: 2),
}) async {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'payment-success',
    barrierColor: Colors.black.withOpacity(0.36),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) {
      return _PosPaymentSuccessDialogBody(
        data: data,
        autoClose: autoClose,
      );
    },
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PosPaymentSuccessDialogBody extends StatefulWidget {
  final PosPaymentSuccessData data;
  final Duration autoClose;

  const _PosPaymentSuccessDialogBody({
    required this.data,
    required this.autoClose,
  });

  @override
  State<_PosPaymentSuccessDialogBody> createState() =>
      _PosPaymentSuccessDialogBodyState();
}

class _PosPaymentSuccessDialogBodyState
    extends State<_PosPaymentSuccessDialogBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdownController;

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: widget.autoClose,
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      })
      ..forward();

    unawaited(_playSuccessFeedback());
  }

  Future<void> _playSuccessFeedback() async {
    try {
      await HapticFeedback.lightImpact();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  @override
  void dispose() {
    _countdownController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cardWidth = size.width > 700 ? 500.0 : size.width - 28;

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withOpacity(0.10)),
          ),
          Center(
            child: Container(
              width: cardWidth.clamp(280, 500),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0xFF34D399).withOpacity(0.35),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.20),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF34D399), Color(0xFF059669)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.28),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF059669).withOpacity(0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.data.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.data.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.78),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _infoRow('Order ID', widget.data.orderId),
                  _infoRow(widget.data.amountLabel, widget.data.amountPaid),
                  _infoRow('Payment Method', widget.data.paymentMethod),
                  _infoRow('Date & Time', widget.data.dateTimeText),
                  if (widget.data.orderedItems.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _orderedItemsSection(widget.data.orderedItems),
                  ],
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _countdownController,
                    builder: (context, _) {
                      final progress = 1.0 - _countdownController.value;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 7,
                              value: progress,
                              backgroundColor: Colors.white.withOpacity(0.22),
                              color: const Color(0xFF34D399),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Auto close...',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.76),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderedItemsSection(List<String> orderedItems) {
    final lines = orderedItems
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final visible = lines.take(4).toList();
    final remaining = lines.length - visible.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ordered Items',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.78),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $line',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (remaining > 0)
            Text(
              '+$remaining more',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.80),
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.78),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
