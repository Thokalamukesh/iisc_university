import 'package:api_selfxo_project/screens/block_screen.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomerBlockScreen(initialTab: 0);
  }
}
