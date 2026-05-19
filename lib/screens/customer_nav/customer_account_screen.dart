import 'package:api_selfxo_project/screens/customer_nav/customer_mobile_number_screen.dart';
import 'package:api_selfxo_project/services/pwa_auth_service.dart';
import 'package:api_selfxo_project/services/session_manager.dart';
import 'package:flutter/material.dart';

class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({super.key});

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  String? _mobileNumber;
  String? _customerName;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _loadCustomerProfile();
  }

  Future<void> _loadCustomerProfile() async {
    final mobile = await SessionManager.instance.getCustomerMobile();
    final customer = await SessionManager.instance.getCustomer();
    final hasSession = await SessionManager.instance.hasSession();
    if (!mounted) return;
    setState(() {
      _mobileNumber = mobile;
      _customerName = customer?['name']?.toString();
      _verified = hasSession && (mobile?.isNotEmpty ?? false);
    });
  }

  Future<void> _openMobileLogin() async {
    final verified = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CustomerMobileNumberScreen()),
    );
    if (!mounted) return;
    if (verified == true) {
      await _loadCustomerProfile();
    }
  }

  Future<void> _signOut() async {
    await PwaAuthService.instance.logout();
    if (!mounted) return;
    setState(() {
      _mobileNumber = null;
      _customerName = null;
      _verified = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _verified && (_mobileNumber?.isNotEmpty ?? false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Account",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEFEFEF)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFFFF5F2),
                        child: Icon(
                          Icons.person_outline,
                          color: Colors.red.shade700,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              signedIn
                                  ? (_customerName?.isNotEmpty == true
                                      ? _customerName!
                                      : "+91 $_mobileNumber")
                                  : "Guest",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              signedIn
                                  ? (_customerName?.isNotEmpty == true
                                      ? "+91 $_mobileNumber"
                                      : "Mobile number verified")
                                  : "Sign in to track orders",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: signedIn ? _signOut : _openMobileLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          signedIn ? Colors.white : const Color(0xFFD32F2F),
                      foregroundColor:
                          signedIn ? const Color(0xFFD32F2F) : Colors.white,
                      elevation: 0,
                      side: signedIn
                          ? const BorderSide(color: Color(0xFFD32F2F))
                          : BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      signedIn ? "Sign Out" : "Sign In with Mobile",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const _AccountAction(
                  icon: Icons.location_on_outlined,
                  title: "Delivery location",
                  subtitle: "Campus Area",
                ),
                const _AccountAction(
                  icon: Icons.help_outline_rounded,
                  title: "Help",
                  subtitle: "Support and order assistance",
                ),
                const _AccountAction(
                  icon: Icons.info_outline_rounded,
                  title: "About SELFX",
                  subtitle: "Food ordering for campus",
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEFEFEF)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ],
      ),
    );
  }
}
