import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';

import 'bmc_screen.dart';
import 'waste_history_screen.dart';
import 'account_screen.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double moistWaste = 0.0;
  double dryWaste = 0.0;
  final double wasteLimit = 5.0;
  int _selectedIndex = 0;
  bool _notified = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _listenToLatestWasteData();
  }

  void _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(initSettings);
  }

  void _showWasteLimitPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("⚠ Waste Limit Exceeded!"),
        content: Text("Your total waste has exceeded $wasteLimit kg. Please manage it efficiently."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))],
      ),
    );
  }

  void _showWasteLimitNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'waste_limit_channel',
      'Waste Limit Alert',
      channelDescription: 'Alerts when waste exceeds the threshold',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      0,
      '⚠ Waste Limit Exceeded!',
      'Your total waste has exceeded $wasteLimit kg.',
      details,
    );
  }

  void _listenToLatestWasteData() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final ref = _db.ref('wasteHistory/$uid')
      ..orderByKey().limitToLast(1).onValue.listen((event) {
        final snapshot = event.snapshot;
        final data = snapshot.value as Map?;
        if (data == null || data.isEmpty) return;

        final lastEntry = data.entries.first.value as Map;

        final double moist = double.tryParse(lastEntry['moistWaste'].toString()) ?? 0.0;
        final double dry = double.tryParse(lastEntry['dryWaste'].toString()) ?? 0.0;

        final totalWaste = (moist + dry) / 1000;

        setState(() {
          moistWaste = moist / 1000;
          dryWaste = dry / 1000;
        });

        if ((moistWaste + dryWaste) > wasteLimit && !_notified) {
          _notified = true;
          _showWasteLimitPopup();
          _showWasteLimitNotification();
        } else if ((moistWaste + dryWaste) <= wasteLimit) {
          _notified = false;
        }
      });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  String _getTitle() {
    return ["Dashboard", "Waste History", "BMC Section", "Account"][_selectedIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green[700],
      ),
      body: _selectedIndex == 0
          ? _buildDashboardContent()
          : _selectedIndex == 1
          ? WasteHistoryScreen()
          : _selectedIndex == 2
          ? BmcScreen()
          : AccountScreen(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blue[800],
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Waste History"),
          BottomNavigationBarItem(icon: Icon(Icons.business), label: "BMC Section"),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: "Account"),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/backgrounds/dashboard_bg.jpg"),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: 50),
          Text("Waste Data", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black)),
          SizedBox(height: 30),
          _buildWasteRow("Moist Waste", moistWaste, "assets/icons/moist_waste.png"),
          SizedBox(height: 20),
          _buildWasteRow("Dry Waste", dryWaste, "assets/icons/dry_waste.png"),
        ],
      ),
    );
  }

  Widget _buildWasteRow(String label, double value, String iconPath) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(iconPath, height: 30),
        SizedBox(width: 10),
        Text("$label: ${value.toStringAsFixed(2)} kg", style: TextStyle(fontSize: 20, color: Colors.black)),
      ],
    );
  }
}