import 'package:api_selfxo_project/screens/login_screen.dart';
import 'package:api_selfxo_project/router/auth_service.dart' as web_auth;
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({super.key});

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  String? _mobileNumber;
  String? _customerName;
  bool _verified = false;
  bool _guest = false;

  @override
  void initState() {
    super.initState();
    _loadCustomerProfile();
  }

  Future<void> _loadCustomerProfile() async {
    final mobile = await SessionManager.instance.getCustomerMobile();
    final customer = await SessionManager.instance.getCustomer();
    final hasSession = await SessionManager.instance.hasSession();
    final isGuest = await SessionManager.instance.isGuestSession();

    if (!mounted) return;

    setState(() {
      _mobileNumber = mobile;
      _customerName = customer?['name']?.toString();
      _verified = hasSession && (mobile?.isNotEmpty ?? false);
      _guest = isGuest && !_verified;
    });
  }

  Future<void> _openMobileLogin() async {
    if (kIsWeb) {
      context.go('/login?force=1');
      return;
    }
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const FoodOtpLoginScreen(),
      ),
    );

    if (!mounted) return;
    if (verified == true) await _loadCustomerProfile();
  }

  Future<void> _signOut() async {
    await web_auth.WebAuthService.instance.logout();

    if (!mounted) return;

    setState(() {
      _mobileNumber = null;
      _customerName = null;
      _verified = false;
      _guest = false;
    });
    if (kIsWeb) {
      context.go('/login?force=1');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _verified && (_mobileNumber?.isNotEmpty ?? false);
    final displayName = signedIn
        ? (_customerName?.trim().isNotEmpty == true
            ? _customerName!.trim()
            : '+91 $_mobileNumber')
        : _guest
            ? 'Guest user'
            : 'Welcome';
    final subtitle = signedIn
        ? '+91 $_mobileNumber'
        : _guest
            ? 'Ordering as guest on this device'
            : 'Sign in to sync orders and receipts';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 14),
          _ProfilePanel(
            displayName: displayName,
            subtitle: subtitle,
            signedIn: signedIn,
            guest: _guest,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: signedIn ? _signOut : _openMobileLogin,
              icon: Icon(
                signedIn ? Icons.logout_rounded : Icons.phone_iphone_rounded,
                size: 19,
              ),
              label: Text(signedIn ? 'Sign out' : 'Sign in with mobile'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor:
                    signedIn ? Colors.white : const Color(0xFFD32F2F),
                foregroundColor:
                    signedIn ? const Color(0xFFD32F2F) : Colors.white,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(
                    color: signedIn
                        ? const Color(0xFFFFC4CB)
                        : const Color(0xFFD32F2F),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _AccountSection(
            title: 'Food profile',
            children: [
              const _AccountAction(
                icon: Icons.location_on_outlined,
                title: 'Campus location',
                subtitle: 'Indian Institute of Science',
                tone: Color(0xFFD32F2F),
              ),
              _AccountAction(
                icon: Icons.receipt_long_rounded,
                title: 'Order history',
                subtitle: signedIn
                    ? 'Saved to your mobile number'
                    : _guest
                        ? 'Saved locally for this guest session'
                        : 'Available after sign in or guest ordering',
                tone: const Color(0xFF2D6CDF),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _AccountSection(
            title: 'Support',
            children: [
              _AccountAction(
                icon: Icons.support_agent_rounded,
                title: 'Help and support',
                subtitle: 'Payment, order, and restaurant assistance',
                tone: Color(0xFF168253),
              ),
              _AccountAction(
                icon: Icons.info_outline_rounded,
                title: 'About SELFX',
                subtitle: 'Campus food ordering for students and staff',
                tone: Color(0xFF7C3AED),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  final String displayName;
  final String subtitle;
  final bool signedIn;
  final bool guest;

  const _ProfilePanel({
    required this.displayName,
    required this.subtitle,
    required this.signedIn,
    required this.guest,
  });

  @override
  Widget build(BuildContext context) {
    final chipText = signedIn
        ? 'Verified'
        : guest
            ? 'Guest'
            : 'Not signed in';
    final chipIcon = signedIn
        ? Icons.verified_rounded
        : guest
            ? Icons.person_outline_rounded
            : Icons.lock_open_rounded;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9ECF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F3),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              signedIn ? Icons.person_rounded : Icons.person_outline_rounded,
              color: const Color(0xFFD32F2F),
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F7FA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        chipIcon,
                        color: const Color(0xFFD32F2F),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        chipText,
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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

class _AccountSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AccountSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF7B8190),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _AccountAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tone;

  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9ECF2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tone.withOpacity(.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: tone, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7B8190),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
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
