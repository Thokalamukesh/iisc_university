import 'dart:convert';

import 'package:api_selfxo_project/api/web_api_config.dart';
import 'package:api_selfxo_project/core/fast_page_route.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/screens/customer_restaurant_selection_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_account_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_offers_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_orders_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Accent palette cycling for dynamically-fetched groups ───────────────────
const List<Color> _kGroupAccents = [
  Color(0xFF2D9CDB),
  Color(0xFF00A884),
  Color(0xFFFF9800),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFF10B981),
];

Color _accentFor(int index) => _kGroupAccents[index % _kGroupAccents.length];

// ─── Data model (populated from API) ─────────────────────────────────────────
class _CustomerBlock {
  final int id;
  final String name;
  final int cafes;
  final Color accent;

  const _CustomerBlock({
    required this.id,
    required this.name,
    required this.cafes,
    required this.accent,
  });

  factory _CustomerBlock.fromJson(Map<String, dynamic> json, int index) {
    final restaurants = (json['restaurants'] as List?)?.length ?? 0;
    return _CustomerBlock(
      id: (json['group_id'] as num).toInt(),
      name: json['group_name']?.toString() ?? 'Block ${index + 1}',
      cafes: restaurants,
      accent: _accentFor(index),
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class CustomerBlockScreen extends StatefulWidget {
  const CustomerBlockScreen({super.key});

  /// Called by the session gate to pre-populate the block cache
  /// so the blocks screen renders without any spinner on first visit.
  static void warmCache(List<dynamic> rawGroups) {
    _CustomerBlockScreenState._cachedBlocks = rawGroups
        .asMap()
        .entries
        .map((e) {
          try {
            return _CustomerBlock.fromJson(
              Map<String, dynamic>.from(e.value as Map),
              e.key,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<_CustomerBlock>()
        .toList();
    _CustomerBlockScreenState._cacheTime = DateTime.now();
  }

  @override
  State<CustomerBlockScreen> createState() => _CustomerBlockScreenState();
}

class _CustomerBlockScreenState extends State<CustomerBlockScreen> {
  static const String _campusImageAsset = "assets/images/iisc-campus-main.jpeg";
  static const Color _brandColor = Color(0xFFFF365A);
  static const Color _brandDarkColor = Color(0xFFD32F2F);
  static const Color _textColor = Color(0xFF111827);
  static const Color _mutedTextColor = Color(0xFF737783);
  static const Color _surfaceColor = Color(0xFFF7F8FB);

  // ── In-memory cache so revisiting the screen is instant ──────────────────
  static List<_CustomerBlock>? _cachedBlocks;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  List<_CustomerBlock> _blocks = [];
  bool _loading = true;
  String? _error;

  int? _selectedBranchId;
  int _selectedBottomIndex = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBlocksFromApi();
  }

  Future<void> _loadBlocksFromApi() async {
    // ── Serve from memory cache if it's fresh ────────────────────────────────
    final cached = _cachedBlocks;
    final cachedAt = _cacheTime;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      final prefs = await SharedPreferences.getInstance();
      final savedBranchId = prefs.getInt('branch_id');
      final validSaved =
          savedBranchId != null && cached.any((b) => b.id == savedBranchId)
              ? savedBranchId
              : null;
      if (!mounted) return;
      setState(() {
        _blocks = cached;
        _selectedBranchId = validSaved;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {'Accept': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final url = WebApiConfig.allRestaurantsUrl;
      kioskLog('Fetching groups from $url', tag: 'BLOCK_SCREEN');
      final res = await dio.get(url);

      if ((res.statusCode ?? 0) >= 400) {
        throw Exception('Server returned ${res.statusCode}');
      }

      final rawData = res.data;
      List<dynamic> list;
      if (rawData is List) {
        list = rawData;
      } else if (rawData is String) {
        list = jsonDecode(rawData) as List<dynamic>;
      } else if (rawData is Map && rawData.containsKey('data')) {
        list = rawData['data'] as List<dynamic>;
      } else {
        list = [];
      }

      final blocks = list
          .asMap()
          .entries
          .map((e) => _CustomerBlock.fromJson(
                Map<String, dynamic>.from(e.value as Map),
                e.key,
              ))
          .toList();

      kioskLog('Loaded ${blocks.length} groups', tag: 'BLOCK_SCREEN');

      // Restore previously saved branch if still valid
      final prefs = await SharedPreferences.getInstance();
      final savedBranchId = prefs.getInt('branch_id');
      final validSaved =
          savedBranchId != null && blocks.any((b) => b.id == savedBranchId)
              ? savedBranchId
              : null;
      if (savedBranchId != null && validSaved == null) {
        await prefs.remove('branch_id');
        await prefs.remove('customer_block_name');
      }

      if (!mounted) return;
      // \u2500\u2500 Write to static cache \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      _cachedBlocks = blocks;
      _cacheTime = DateTime.now();
      setState(() {
        _blocks = blocks;
        _selectedBranchId = validSaved;
        _loading = false;
      });
    } catch (e, st) {
      kioskLogError('Failed to load groups: $e',
          tag: 'BLOCK_SCREEN', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load blocks. Please check your connection.';
      });
    }
  }

  Future<void> _selectBlock(_CustomerBlock block) async {
    if (_saving) return;
    setState(() {
      _selectedBranchId = block.id;
      _saving = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('branch_id', block.id);
    await prefs.setString('customer_block_name', block.name);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      fastPageRoute((_) => const CustomerRestaurantSelectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceColor,
      body: SafeArea(
        bottom: false,
        child: _buildSelectedTab(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        selectedItemColor: _brandDarkColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedBottomIndex,
        onTap: (index) => setState(() => _selectedBottomIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined), label: 'Orders'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_offer_outlined), label: 'Offers'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }

  Widget _buildSelectedTab() {
    switch (_selectedBottomIndex) {
      case 1:
        return const CustomerOrdersScreen();
      case 2:
        return const CustomerOffersScreen();
      case 3:
        return const CustomerAccountScreen();
      case 0:
      default:
        return _buildBlockSelection();
    }
  }

  Widget _buildBlockSelection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final horizontalPadding = isWide ? 24.0 : 16.0;
        final contentWidth =
            constraints.maxWidth > 680 ? 680.0 : constraints.maxWidth;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      18,
                    ),
                    children: [
                      _HeroHeader(onBack: _handleBack),
                      const SizedBox(height: 10),
                      const _CampusCard(),
                      const SizedBox(height: 14),
                      const Text(
                        'Available Blocks',
                        style: TextStyle(
                          color: _textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_error != null)
                        _ErrorState(
                          message: _error!,
                          onRetry: _loadBlocksFromApi,
                        )
                      else if (_blocks.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Text(
                              'No blocks available at the moment.',
                              style: TextStyle(
                                color: _mutedTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else if (isWide)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _blocks.map((block) {
                            return SizedBox(
                              width:
                                  (contentWidth - (horizontalPadding * 2) - 12) /
                                      2,
                              child: _BlockCard(
                                block: block,
                                selected: _selectedBranchId == block.id,
                                disabled: _saving,
                                onTap: () => _selectBlock(block),
                              ),
                            );
                          }).toList(),
                        )
                      else
                        ..._blocks.map((block) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BlockCard(
                              block: block,
                              selected: _selectedBranchId == block.id,
                              disabled: _saving,
                              onTap: () => _selectBlock(block),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }
}

// ─── Error state ──────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 48, color: Color(0xFFBDBDBD)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF737783),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF365A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero header ──────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _HeroHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFD4BF),
            Color(0xFFFFE9C7),
            Color(0xFFEAD8FF),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackButton(onTap: onBack),
                const SizedBox(height: 10),
                const Text(
                  'Select Your\nCanteen Block',
                  style: TextStyle(
                    color: _CustomerBlockScreenState._textColor,
                    fontSize: 25,
                    height: 1.04,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pick your block to view available restaurants and services.',
                  style: TextStyle(
                    color: Color(0xFF5F6470),
                    fontSize: 13,
                    height: 1.32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            flex: 8,
            child: SizedBox(
              height: 128,
              child: _CampusIllustration(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: const SizedBox(
          width: 44,
          height: 40,
          child: Icon(
            Icons.arrow_back_rounded,
            color: _CustomerBlockScreenState._textColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _CampusIllustration extends StatelessWidget {
  const _CampusIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: 0,
          top: 4,
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.82),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B4A32).withOpacity(0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(5),
            child: ClipOval(
              child: Image.asset(
                _CustomerBlockScreenState._campusImageAsset,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.school_rounded,
                  size: 48,
                  color: Color(0xFFFF365A),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 72,
          bottom: 10,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFFFD5DF), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: _CustomerBlockScreenState._brandColor,
              size: 28,
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 0,
          child: Container(
            width: 82,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: Colors.white.withOpacity(0.86),
              border: Border.all(color: Colors.white.withOpacity(0.92)),
            ),
            alignment: Alignment.center,
            child: const Text(
              'IISC Campus',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF9F342C),
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Positioned(
          right: -4,
          top: 0,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFF2D7).withOpacity(0.88),
            ),
          ),
        ),
      ],
    );
  }
}

class _CampusCard extends StatelessWidget {
  const _CampusCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: const Color(0xFFFFD5DF),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: Image.asset(
                  _CustomerBlockScreenState._campusImageAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.school_rounded,
                    size: 28,
                    color: Color(0xFFFF365A),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current Campus',
                  style: TextStyle(
                    color: _CustomerBlockScreenState._mutedTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Indian Institute of Science (IISC)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _CustomerBlockScreenState._textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Block card ───────────────────────────────────────────────────────────────
class _BlockCard extends StatelessWidget {
  final _CustomerBlock block;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _BlockCard({
    required this.block,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? _CustomerBlockScreenState._brandColor
                  : const Color(0xFFE8EAF0),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.055),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BlockThumbnail(accent: block.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            block.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _CustomerBlockScreenState._textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected
                              ? _CustomerBlockScreenState._brandColor
                              : const Color(0xFFC8CBD4),
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _BlockStat(
                          icon: Icons.restaurant_rounded,
                          value: '${block.cafes}',
                          label: block.cafes == 1 ? 'Cafe' : 'Cafes',
                        ),
                        const _BlockStat(
                          icon: Icons.bolt_rounded,
                          value: '',
                          label: 'Fast Service',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockThumbnail extends StatelessWidget {
  final Color accent;

  const _BlockThumbnail({required this.accent});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 88,
        height: 78,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFDDF5FF), Color(0xFFF4FBF8)],
            ),
          ),
          child: CustomPaint(
            painter: _BlockThumbnailPainter(accent),
          ),
        ),
      ),
    );
  }
}

class _BlockStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _BlockStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 82,
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF6E7280)),
          const SizedBox(width: 5),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFF6E7280),
                  fontSize: 11,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                ),
                children: [
                  if (value.isNotEmpty)
                    TextSpan(
                      text: '$value\n',
                      style: const TextStyle(
                        color: _CustomerBlockScreenState._textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  TextSpan(text: label),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockThumbnailPainter extends CustomPainter {
  final Color accent;

  const _BlockThumbnailPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(.12);
    final bodyPaint = Paint()..color = accent;
    final sidePaint = Paint()..color = Color.lerp(accent, Colors.black, .18)!;
    final windowPaint = Paint()..color = Colors.white.withOpacity(.56);
    final treePaint = Paint()..color = const Color(0xFF48A868);
    final trunkPaint = Paint()..color = const Color(0xFF8A5D3B);

    canvas.drawOval(
      Rect.fromLTWH(size.width * .10, size.height * .78, size.width * .80, 13),
      shadowPaint,
    );

    final front = Path()
      ..moveTo(size.width * .23, size.height * .22)
      ..lineTo(size.width * .69, size.height * .12)
      ..lineTo(size.width * .69, size.height * .76)
      ..lineTo(size.width * .23, size.height * .84)
      ..close();
    final side = Path()
      ..moveTo(size.width * .69, size.height * .12)
      ..lineTo(size.width * .85, size.height * .24)
      ..lineTo(size.width * .85, size.height * .82)
      ..lineTo(size.width * .69, size.height * .76)
      ..close();

    canvas.drawPath(front, bodyPaint);
    canvas.drawPath(side, sidePaint);

    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 3; col++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * (.30 + col * .12),
              size.height * (.31 + row * .12),
              size.width * .07,
              size.height * .055,
            ),
            const Radius.circular(1.5),
          ),
          windowPaint,
        );
      }
    }

    for (var row = 0; row < 4; row++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * .74,
            size.height * (.31 + row * .12),
            size.width * .06,
            size.height * .05,
          ),
          const Radius.circular(1.5),
        ),
        windowPaint,
      );
    }

    for (final dx in [.18, .88]) {
      final x = size.width * dx;
      final y = size.height * .80;
      canvas.drawRect(Rect.fromLTWH(x - 1.5, y - 16, 3, 17), trunkPaint);
      canvas.drawCircle(Offset(x, y - 19), 8, treePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlockThumbnailPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
