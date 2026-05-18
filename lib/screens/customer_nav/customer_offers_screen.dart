import 'package:flutter/material.dart';

class CustomerOffersScreen extends StatelessWidget {
  const CustomerOffersScreen({super.key});

  static const List<String> _offerBanners = [
    "assets/images/selfx-banner-1.jpg.jpeg",
    "assets/images/selfx-banner-2.jpg.jpeg",
    "assets/images/selfx-banner-3.jpg.jpeg",
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Offers",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 14),
                ..._offerBanners.map(
                  (asset) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 1.27,
                        child: Image.asset(
                          asset,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
