import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:api_selfxo_project/api/web_api_config.dart';
import 'package:api_selfxo_project/core/fast_page_route.dart';
import 'package:api_selfxo_project/core/kiosk_log.dart';
import 'package:api_selfxo_project/screens/customer_restaurant_selection_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_account_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_offers_screen.dart';
import 'package:api_selfxo_project/screens/customer_nav/customer_orders_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    final rawId =
        json['group_id'] ?? json['groupId'] ?? json['branch_id'] ?? json['id'];
    final parsedId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    return _CustomerBlock(
      id: parsedId ?? index + 1,
      name: json['group_name']?.toString().trim().isNotEmpty == true
          ? json['group_name'].toString()
          : json['name']?.toString().trim().isNotEmpty == true
              ? json['name'].toString()
              : 'Block ${index + 1}',
      cafes: restaurants,
      accent: _accentFor(index),
    );
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class CustomerBlockScreen extends StatefulWidget {
  final int initialTab;

  const CustomerBlockScreen({
    super.key,
    this.initialTab = 0,
  });

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
  static const Color _surfaceColor = Color(0xFFF4F6FA);
  static const String _diskCacheKey = 'customer_block_groups_cache_v1';

  // ── In-memory cache so revisiting the screen is instant ──────────────────
  static List<_CustomerBlock>? _cachedBlocks;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  List<_CustomerBlock> _blocks = [];
  bool _loading = true;
  String? _error;

  int? _selectedBranchId;
  late int _selectedBottomIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedBottomIndex = widget.initialTab.clamp(0, 3).toInt();
    _loadBlocksFromApi();
  }

  @override
  void didUpdateWidget(covariant CustomerBlockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _selectedBottomIndex = widget.initialTab.clamp(0, 3).toInt();
      });
    }
  }

  Future<void> _loadBlocksFromApi() async {
    // ── Serve from memory cache if it's fresh ────────────────────────────────
    final cached = _cachedBlocks;
    final cachedAt = _cacheTime;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      if (!mounted) return;
      setState(() {
        _blocks = cached;
        _selectedBranchId = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    var showingCachedBlocks = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final diskBlocks = _readBlocksFromDiskCache(prefs);
      if (diskBlocks.isNotEmpty && mounted) {
        showingCachedBlocks = true;
        setState(() {
          _blocks = diskBlocks;
          _selectedBranchId = null;
          _loading = false;
          _error = null;
        });
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {'Accept': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      const url = WebApiConfig.allRestaurantsUrl;
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
        final decoded = jsonDecode(rawData);
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map) {
          final rawList =
              decoded['data'] ?? decoded['groups'] ?? decoded['items'];
          list = rawList is List ? rawList : const [];
        } else {
          list = const [];
        }
      } else if (rawData is Map) {
        final rawList =
            rawData['data'] ?? rawData['groups'] ?? rawData['items'];
        list = rawList is List ? rawList : const [];
      } else {
        list = [];
      }

      final blocks = list
          .asMap()
          .entries
          .map((e) {
            final value = e.value;
            if (value is! Map) return null;
            return _CustomerBlock.fromJson(
              Map<String, dynamic>.from(value),
              e.key,
            );
          })
          .whereType<_CustomerBlock>()
          .toList();

      kioskLog('Loaded ${blocks.length} groups', tag: 'BLOCK_SCREEN');

      // Clear stale saved branch data, but do not pre-select a block visually.
      final savedBranchId = prefs.getInt('branch_id');
      final savedStillExists =
          savedBranchId != null && blocks.any((b) => b.id == savedBranchId);
      if (savedBranchId != null && !savedStillExists) {
        await prefs.remove('branch_id');
        await prefs.remove('customer_block_name');
      }
      await _writeBlocksToDiskCache(prefs, list);

      if (!mounted) return;
      // \u2500\u2500 Write to static cache \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
      _cachedBlocks = blocks;
      _cacheTime = DateTime.now();
      setState(() {
        _blocks = blocks;
        _selectedBranchId = null;
        _loading = false;
      });
    } catch (e, st) {
      kioskLogError('Failed to load groups: $e',
          tag: 'BLOCK_SCREEN', error: e, stackTrace: st);
      if (!mounted) return;
      if (showingCachedBlocks) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load blocks. Please check your connection.';
      });
    }
  }

  List<_CustomerBlock> _readBlocksFromDiskCache(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_diskCacheKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      final rawList = decoded is Map ? decoded['groups'] : decoded;
      if (rawList is! List) return const [];
      return rawList
          .asMap()
          .entries
          .map((entry) {
            final value = entry.value;
            if (value is! Map) return null;
            return _CustomerBlock.fromJson(
              Map<String, dynamic>.from(value),
              entry.key,
            );
          })
          .whereType<_CustomerBlock>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeBlocksToDiskCache(
    SharedPreferences prefs,
    List<dynamic> groups,
  ) async {
    try {
      await prefs.setString(
        _diskCacheKey,
        jsonEncode({
          'cached_at': DateTime.now().millisecondsSinceEpoch,
          'groups': groups,
        }),
      );
    } catch (_) {}
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
    final isHomeTab = _selectedBottomIndex == 0;

    return Scaffold(
      extendBodyBehindAppBar: isHomeTab,
      backgroundColor: _surfaceColor,
      body: SafeArea(
        top: !isHomeTab,
        bottom: false,
        child: _buildSelectedTab(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        elevation: 14,
        selectedItemColor: _brandDarkColor,
        unselectedItemColor: const Color(0xFF8A90A0),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedBottomIndex,
        onTap: _handleBottomNavigationTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer_outlined),
            label: 'Offers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Account',
          ),
        ],
      ),
    );
  }

  void _handleBottomNavigationTap(int index) {
    if (kIsWeb) {
      final target = switch (index) {
        0 => '/home',
        1 => '/orders',
        2 => '/offers',
        3 => '/profile',
        _ => '/home',
      };
      final current = GoRouterState.of(context).uri.path;
      if (current == target) return;
      context.go(target);
      return;
    }
    setState(() => _selectedBottomIndex = index);
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
            constraints.maxWidth > 760 ? 760.0 : constraints.maxWidth;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 22),
                    children: [
                      _BlockTopBar(
                        loading: _loading,
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          20,
                          horizontalPadding,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Available Blocks',
                                    style: TextStyle(
                                      color: _textColor,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
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
                                    width: (contentWidth -
                                            (horizontalPadding * 2) -
                                            12) /
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
                                  padding: const EdgeInsets.only(bottom: 12),
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
              ],
            ),
          ),
        );
      },
    );
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

// ─── Header ──────────────────────────────────────────────────────────────────
class _BlockTopBar extends StatelessWidget {
  final bool loading;

  const _BlockTopBar({
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 318,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.16),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _CustomerBlockScreenState._campusImageAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF111827),
                child: const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(.08),
                    Colors.black.withOpacity(.28),
                    Colors.black.withOpacity(.74),
                  ],
                  stops: const [.0, .48, 1],
                ),
              ),
            ),
            const Positioned(
              left: 20,
              right: 20,
              bottom: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select your canteen',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.03,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Choose a campus block to view available restaurants.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFECEFF4),
                      fontSize: 14,
                      height: 1.34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.18),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(.28)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.22),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.location_on_outlined,
                            color: Colors.white,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'IISC Campus',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFFECEFF4),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                loading ? 'Loading canteens' : 'Campus dining',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    final restaurantLabel =
        '${block.cafes} ${block.cafes == 1 ? 'restaurant' : 'restaurants'}';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? _CustomerBlockScreenState._brandColor
                  : const Color(0xFFE6EAF1),
              width: selected ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.035),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: block.accent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.apartment_rounded,
                  color: block.accent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _CustomerBlockScreenState._textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _BlockBadge(
                          icon: Icons.restaurant_menu_rounded,
                          label: restaurantLabel,
                          tone: block.accent,
                        ),
                        const _BlockBadge(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Open',
                          tone: Color(0xFF168253),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        Icon(
                          Icons.near_me_rounded,
                          color: Color(0xFF8A90A0),
                          size: 15,
                        ),
                        SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Inside campus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF7B8190),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? _CustomerBlockScreenState._brandColor
                      : block.accent.withOpacity(.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  selected ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  color: selected ? Colors.white : block.accent,
                  size: 21,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;

  const _BlockBadge({
    required this.icon,
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withOpacity(.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tone, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Color.lerp(tone, Colors.black, .18),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
