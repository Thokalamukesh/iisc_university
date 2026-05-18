import 'package:api_selfxo_project/screens/customer_restaurant_selection_screen.dart';
import 'package:flutter/material.dart';

class CompanyBlockSelectionScreen extends StatefulWidget {
  const CompanyBlockSelectionScreen({super.key});

  @override
  State<CompanyBlockSelectionScreen> createState() =>
      _CompanyBlockSelectionScreenState();
}

class _CompanyBlockSelectionScreenState
    extends State<CompanyBlockSelectionScreen> {
  final Color primary = const Color(0xFFA3211C);
  final Color bg = const Color(0xFFF8F5F4);

  int selectedIndex = -1;

  final List<Map<String, dynamic>> blocks = [
    {"name": "Block A", "canteen": "Main Meals", "icon": Icons.apartment},
    {"name": "Block B", "canteen": "Food Court", "icon": Icons.apartment},
    {"name": "Block C", "canteen": "Snack Zone", "icon": Icons.apartment},
    {"name": "Block D", "canteen": "Executive", "icon": Icons.apartment},
    {"name": "Block E", "canteen": "Healthy Hub", "icon": Icons.apartment},
    {"name": "Block F", "canteen": "Quick Bite", "icon": Icons.apartment},
  ];

  void continueNext() {
    if (selectedIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select your block first 😅"),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const CustomerRestaurantSelectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    const Text(
                      "Choose Your Block 🏢",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Pick your office block for faster food delivery & nearest canteen 🍔",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: GridView.builder(
                        itemCount: blocks.length,
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.12,
                        ),
                        itemBuilder: (context, index) {
                          return _gridCard(index);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: continueNext,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          "Continue 🚀",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            primary.withOpacity(.92),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(30),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            "Select Location",
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridCard(int index) {
    final item = blocks[index];
    final selected = selectedIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        setState(() {
          selectedIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? primary : Colors.grey.shade300,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? primary : Colors.grey.shade400,
              ),
            ),
            Container(
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: primary.withOpacity(.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                item["icon"],
                size: 54,
                color: primary,
              ),
            ),
            Text(
              item["name"],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              item["canteen"],
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
