import 'package:flutter/material.dart';

class RevenueCards extends StatelessWidget {
  final Map stats;
  const RevenueCards({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final revenue = (stats["revenue"] ?? 0).toDouble();
    final orders = stats["orders"] ?? 0;

    return Row(
      children: [
        _card("Revenue", "₹${revenue.toStringAsFixed(2)}", Colors.green),
        _card("Orders", "$orders", Colors.blue),
      ],
    );
  }

  Widget _card(String title, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
