import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dashboard_screen.dart';

class BmcScreen extends StatelessWidget {
  final List<Map<String, String>> bmcCenters = [
    {"name": "BMC Office - Andheri", "phone": "022-12345678"},
    {"name": "BMC Office - Bandra", "phone": "022-87654321"},
    {"name": "BMC Office - Dadar", "phone": "022-56781234"},
    {"name": "BMC Office - Borivali", "phone": "022-43218765"},
  ];

  void _callNumber(BuildContext context, String phoneNumber) async {
    final Uri callUri = Uri(scheme: "tel", path: phoneNumber);
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not launch $phoneNumber"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => DashboardScreen()),
            );
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/backgrounds/bmc_bg.jpg"),
            fit: BoxFit.cover,
          ),
        ),
        padding: EdgeInsets.only(top: kToolbarHeight + 40, left: 15, right: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Only this title is visible now
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              margin: EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "BMC Offices",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 4,
                      color: Colors.black87,
                      offset: Offset(1.5, 1.5),
                    ),
                  ],
                ),
              ),
            ),

            // 📞 Contact Cards
            Expanded(
              child: ListView.builder(
                itemCount: bmcCenters.length,
                itemBuilder: (context, index) {
                  final center = bmcCenters[index];
                  return Card(
                    color: Colors.white.withOpacity(0.9),
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(
                        center["name"]!,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text("📞 Contact: ${center["phone"]!}"),
                      trailing: IconButton(
                        icon: Icon(Icons.call, color: Colors.green, size: 28),
                        onPressed: () => _callNumber(context, center["phone"]!),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}