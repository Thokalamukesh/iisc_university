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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: const Color(0xFFD32F2F),
        child: FutureBuilder<List<CustomerOrderHistoryItem>>(
          future: _ordersFuture,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            final orders = snapshot.data ?? const <CustomerOrderHistoryItem>[];

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _OrdersHeader(
                    orderCount: loading ? null : orders.length,
                    onRefresh: _refresh,
                  ),
                ),
                if (loading)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 20),
                    sliver: _OrdersLoadingList(),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _OrdersErrorState(onRetry: _refresh),
                  )
                else if (orders.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  _OrdersTabbedList(
                    orders: orders,
                    onRefresh: _refresh,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OrdersTabbedList extends StatelessWidget {
  final List<CustomerOrderHistoryItem> orders;
  final Future<void> Function() onRefresh;

  const _OrdersTabbedList({
    required this.orders,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final activeOrders =
        orders.where((order) => !_isCancelledOrder(order)).toList();
    final cancelled = orders.where(_isCancelledOrder).toList();

    return SliverFillRemaining(
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: _OrdersSegmentedTabs(),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _OrdersTabList(
                    orders: activeOrders,
                    onRefresh: onRefresh,
                    emptyIcon: Icons.receipt_long_rounded,
                    emptyText: 'No orders yet.',
                  ),
                  _OrdersTabList(
                    orders: cancelled,
                    onRefresh: onRefresh,
                    emptyIcon: Icons.cancel_outlined,
                    emptyText: 'No cancelled orders.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrdersSegmentedTabs extends StatelessWidget {
  const _OrdersSegmentedTabs();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9ECF2)),
      ),
      child: TabBar(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: const Color(0xFFD32F2F),
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF6B7280),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        tabs: const [
          Tab(text: 'Orders'),
          Tab(text: 'Cancelled'),
        ],
      ),
    );
  }
}

class _OrdersTabList extends StatelessWidget {
  final List<CustomerOrderHistoryItem> orders;
  final Future<void> Function() onRefresh;
  final IconData emptyIcon;
  final String emptyText;

  const _OrdersTabList({
    required this.orders,
    required this.onRefresh,
    required this.emptyIcon,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: const Color(0xFFD32F2F),
      child: orders.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _TabEmptyState(
                  icon: emptyIcon,
                  text: emptyText,
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _OrderHistoryCard(
                order: orders[index],
              ),
            ),
    );
  }
}

class _TabEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TabEmptyState({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9ECF2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFADB4C2), size: 28),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF7B8190),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrdersHeader extends StatelessWidget {
  final int? orderCount;
  final Future<void> Function() onRefresh;

  const _OrdersHeader({
    required this.orderCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final countText = orderCount == null
        ? 'Syncing orders'
        : orderCount == 1
            ? '1 order'
            : '$orderCount orders';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Orders',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  countText,
                  style: const TextStyle(
                    color: Color(0xFF7B8190),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE7EAF0)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistoryCard extends StatelessWidget {
  final CustomerOrderHistoryItem order;

  const _OrderHistoryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);
    final items =
        order.items.where((item) => _itemName(item).isNotEmpty).toList();
    final extraCount = items.length > 2 ? items.length - 2 : 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showOrderDetails(context, order),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE9ECF2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.035),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.restaurantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Order #${order.orderId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF7B8190),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _money(order.totalAmount),
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (items.isNotEmpty)
                ...items.take(2).map((item) => _OrderItemPreview(item: item))
              else
                const Text(
                  'Order items will appear here when available.',
                  style: TextStyle(
                    color: Color(0xFF7B8190),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (extraCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '+ $extraCount more item${extraCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFFD32F2F),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  _StatusPill(
                      label: _statusLabel(order.status), color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatOrderDate(order),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8A90A0),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.receipt_long_rounded,
                    size: 19,
                    color: Color(0xFFADB4C2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderItemPreview extends StatelessWidget {
  final Map<String, dynamic> item;

  const _OrderItemPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final price = _itemAmount(item);
    final image = _itemImage(item);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          _ItemThumb(image: image, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _itemName(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_itemQuantity(item)} item${_itemQuantity(item) == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF7B8190),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (price > 0)
            Text(
              _money(price),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailsSheet extends StatelessWidget {
  final CustomerOrderHistoryItem order;

  const _OrderDetailsSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);
    final items =
        order.items.where((item) => _itemName(item).isNotEmpty).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6DAE2),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.restaurantName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Order #${order.orderId} • ${_formatOrderDate(order)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF7B8190),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(
                    label: _statusLabel(order.status), color: statusColor),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1, color: Color(0xFFE9ECF2)),
            const SizedBox(height: 14),
            const Text(
              'Items',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Item details are not available for this order.',
                  style: TextStyle(
                    color: Color(0xFF7B8190),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              ...items.take(8).map((item) => _OrderItemRow(item: item)),
            const SizedBox(height: 14),
            if (order.paymentMethod.isNotEmpty ||
                order.transactionId.isNotEmpty) ...[
              _PaymentSummary(order: order),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FA),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Order total',
                      style: TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    _money(order.totalAmount),
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _OrderItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final price = _itemAmount(item);
    final image = _itemImage(item);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _ItemThumb(image: image, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _itemName(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Qty ${_itemQuantity(item)}',
                  style: const TextStyle(
                    color: Color(0xFF7B8190),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (price > 0)
            Text(
              _money(price),
              style: const TextStyle(
                color: Color(0xFF4B5563),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  final CustomerOrderHistoryItem order;

  const _PaymentSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    final method = order.paymentMethod.trim();
    final transactionId = order.transactionId.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF8F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCDEDDD)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF168253),
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payment successful',
                  style: TextStyle(
                    color: Color(0xFF116B45),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (method.isNotEmpty || transactionId.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (method.isNotEmpty) method,
                      if (transactionId.isNotEmpty) transactionId,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4B8067),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  final String image;
  final double size;

  const _ItemThumb({
    required this.image,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFF1F3F7),
        child: image.isEmpty
            ? const Icon(
                Icons.fastfood_rounded,
                color: Color(0xFFADB4C2),
                size: 22,
              )
            : Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.fastfood_rounded,
                  color: Color(0xFFADB4C2),
                  size: 22,
                ),
              ),
      ),
    );
  }
}

class _OrdersLoadingList extends StatelessWidget {
  const _OrdersLoadingList();

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        height: 138,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9ECF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _loadingBar(width: 150, height: 16)),
                const SizedBox(width: 18),
                _loadingBar(width: 58, height: 18),
              ],
            ),
            const SizedBox(height: 12),
            _loadingBar(width: double.infinity, height: 12),
            const SizedBox(height: 8),
            _loadingBar(width: 190, height: 12),
            const Spacer(),
            _loadingBar(width: 110, height: 28),
          ],
        ),
      ),
    );
  }

  Widget _loadingBar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDEFF4),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _OrdersErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _OrdersErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFADB4C2),
              size: 44,
            ),
            const SizedBox(height: 14),
            const Text(
              'Orders could not be loaded',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pull down to refresh or try again in a moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7B8190),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE9ECF2)),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 38,
                color: Color(0xFFD32F2F),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No orders yet',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your paid orders will appear here with status, items, and receipt details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7B8190),
                height: 1.38,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showOrderDetails(BuildContext context, CustomerOrderHistoryItem order) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => _OrderDetailsSheet(order: order),
  );
}

Color _statusColor(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized.contains('paid') ||
      normalized.contains('success') ||
      normalized.contains('completed') ||
      normalized.contains('delivered')) {
    return const Color(0xFF168253);
  }
  if (normalized.contains('pending') ||
      normalized.contains('processing') ||
      normalized.contains('preparing') ||
      normalized.contains('accepted') ||
      normalized.contains('progress') ||
      normalized.contains('due') ||
      normalized.contains('unpaid')) {
    return const Color(0xFFC56A00);
  }
  if (normalized.contains('cancel') || normalized.contains('failed')) {
    return const Color(0xFFC62828);
  }
  return const Color(0xFF42618A);
}

bool _isCancelledOrder(CustomerOrderHistoryItem order) {
  final status = order.status.trim().toLowerCase();
  return status.contains('cancel') ||
      status.contains('failed') ||
      status.contains('rejected') ||
      status.contains('refunded');
}

String _statusLabel(String status) {
  final cleaned = status.trim();
  if (cleaned.isEmpty) return 'Paid';
  return cleaned
      .split(RegExp(r'[\s_]+'))
      .where((part) => part.isNotEmpty)
      .map((part) =>
          '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

String _formatOrderDate(CustomerOrderHistoryItem order) {
  final backendFormatted = order.displayDateTime.trim();
  if (backendFormatted.isNotEmpty) return backendFormatted;
  return _formatDate(order.orderedAt.toLocal());
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day/$month/$year, $hour:$minute';
}

String _money(double value) {
  final fixed = value.truncateToDouble() == value
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '₹$fixed';
}

String _itemName(Map<String, dynamic> item) {
  return (item['name'] ?? item['item_name'] ?? item['itemName'] ?? '')
      .toString()
      .trim();
}

int _itemQuantity(Map<String, dynamic> item) {
  final raw = item['quantity'] ?? item['qty'] ?? item['count'];
  final parsed = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  return parsed == null || parsed <= 0 ? 1 : parsed;
}

double _itemAmount(Map<String, dynamic> item) {
  final raw = item['amount'] ??
      item['total'] ??
      item['total_amount'] ??
      item['totalAmount'] ??
      item['price'] ??
      item['itemPrice'];
  return raw is num
      ? raw.toDouble()
      : double.tryParse(raw?.toString() ?? '') ?? 0;
}

String _itemImage(Map<String, dynamic> item) {
  return (item['image'] ??
          item['image_url'] ??
          item['imageUrl'] ??
          item['item_image_url'] ??
          item['item_photo_url'] ??
          item['itemPhotoUrl'] ??
          item['photo_url'] ??
          item['photoUrl'] ??
          item['thumbnail_url'] ??
          item['product_image'] ??
          '')
      .toString()
      .trim();
}
