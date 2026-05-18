import 'package:flutter/material.dart';

class CustomerAuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const CustomerAuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  static const Color brandColor = Color(0xFFD32F2F);
  static const Color surfaceColor = Color(0xFFF7F7F8);
  static const Color textColor = Color(0xFF171717);
  static const Color mutedTextColor = Color(0xFF6F6F76);
  static const String logoAsset = 'assets/lo.png';
  static const String headerImageAsset =
      'assets/images/login_food_background.jpg';

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: surfaceColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final isCompact = viewport.maxWidth < 420;
            final horizontalPadding = isCompact ? 16.0 : 24.0;

            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: isCompact ? 18 : 28),
              child: Column(
                children: [
                  _AuthHeader(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    canPop: canPop,
                    horizontalPadding: horizontalPadding,
                  ),
                  Transform.translate(
                    offset: const Offset(0, -30),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFFE8E8EC),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x16000000),
                                  blurRadius: 30,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(isCompact ? 18 : 24),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool canPop;
  final double horizontalPadding;

  const _AuthHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.canPop,
    required this.horizontalPadding,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(30),
      ),
      child: SizedBox(
        height: 280,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              CustomerAuthLayout.headerImageAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0xB8000000),
                    Color(0xE0000000),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                14,
                horizontalPadding,
                34,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (canPop) ...[
                        _CircleIconButton(
                          icon: Icons.arrow_back_rounded,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 12),
                      ],
                      const _LogoMark(),
                    ],
                  ),
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.28),
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 32),
                    ),
                  ),
                  if (title.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ) ??
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                          ),
                    ),
                  ],
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFE9E9E9),
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ) ??
                          const TextStyle(
                            color: Color(0xFFE9E9E9),
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      width: 126,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Image.asset(
        CustomerAuthLayout.logoAsset,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        tooltip: 'Back',
      ),
    );
  }
}
