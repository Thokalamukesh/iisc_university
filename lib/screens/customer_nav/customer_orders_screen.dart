import 'package:api_selfxo_project/services/customer_order_history_service.dart';
import 'package:flutter/material.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  late Future<List<CustomerOrderHistoryItem>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = CustomerOrderHistoryService.instance.loadOrders();
  }

  Future<void> _refresh() async {
    setState(() {
      _ordersFuture = CustomerOrderHistoryService.instance.loadOrders();
    });
    await _ordersFuture;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<CustomerOrderHistoryItem>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          final orders = snapshot.data ?? const <CustomerOrderHistoryItem>[];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Orders",
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 14),
                      if (snapshot.connectionState != ConnectionState.done)
                        const _OrdersLoading()
                      else if (orders.isEmpty)
                        const _EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: "No orders yet",
                          subtitle:
                              "Paid restaurant orders from this mobile number will appear here.",
                        )
                      else
                        ...orders.map((order) => _OrderHistoryCard(order)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  final CustomerOrderHistoryItem order;

  const _OrderHistoryCard(this.order);

  @override
  Widget build(BuildContext context) {
    final itemPreview = order.items
        .map((item) => item["name"]?.toString() ?? "")
        .where((name) => name.trim().isNotEmpty)
        .take(2)
        .join(", ");

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEFEF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF7EF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.restaurantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Order #${order.orderId}",
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "₹${order.totalAmount.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF9F342C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            itemPreview.isEmpty
                ? "${order.itemCount} item${order.itemCount == 1 ? "" : "s"}"
                : itemPreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _OrderChip(label: order.status),
              const SizedBox(width: 8),
              _OrderChip(label: _formatDate(order.orderedAt)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, "0");
    final month = value.month.toString().padLeft(2, "0");
    final hour = value.hour.toString().padLeft(2, "0");
    final minute = value.minute.toString().padLeft(2, "0");
    return "$day/$month $hour:$minute";
  }
}

class _OrderChip extends StatelessWidget {
  final String label;

  const _OrderChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1E3DE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.black54,
        ),
      ),
    );
  }
}

class _OrdersLoading extends StatelessWidget {
  const _OrdersLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 46, color: Colors.red.shade300),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, height: 1.35),
          ),
        ],
      ),
    );
  }
}
