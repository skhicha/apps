import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class WasteHistoryScreen extends StatefulWidget {
  @override
  _WasteHistoryScreenState createState() => _WasteHistoryScreenState();
}

class _WasteHistoryScreenState extends State<WasteHistoryScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> wasteLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchWasteHistory();
  }

  void _fetchWasteHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final DatabaseReference _dbRef =
    FirebaseDatabase.instance.ref().child('wasteHistory').child(uid);

    _dbRef.onValue.listen((event) {
      final snapshot = event.snapshot;
      final data = snapshot.value;

      if (data == null) {
        setState(() {
          wasteLogs.clear();
          _loading = false;
        });
        return;
      }

      try {
        final historyMap = Map<String, dynamic>.from(data as Map);
        final List<Map<String, dynamic>> loadedLogs = [];

        historyMap.forEach((key, value) {
          final log = Map<String, dynamic>.from(value);
          loadedLogs.add({
            'timestamp': log['timestamp'] ?? int.tryParse(key) ?? 0,
            'moistWaste': log['moistWaste'] ?? 0.0,
            'dryWaste': log['dryWaste'] ?? 0.0,
          });
        });

        // Sort by newest first
        loadedLogs.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

        setState(() {
          wasteLogs = loadedLogs;
          _loading = false;
        });
      } catch (e) {
        print("❌ Error parsing waste history: $e");
        setState(() {
          wasteLogs = [];
          _loading = false;
        });
      }
    }, onError: (error) {
      print("❌ Firebase error: $error");
      setState(() {
        wasteLogs = [];
        _loading = false;
      });
    });
  }

  String formatTimestamp(int timestamp) {
    try {
      // Convert the timestamp to DateTime (UTC)
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);

      // Adjust for IST (UTC +5:30)
      DateTime localDt = dt.add(Duration(hours: 5, minutes: 30));

      // Format the date and time
      return DateFormat('dd MMM yyyy – hh:mm a').format(localDt);
    } catch (_) {
      return "Invalid timestamp";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage("assets/backgrounds/history_bg.jpg"),
          fit: BoxFit.cover,
        ),
      ),
      child: _loading
          ? Center(child: CircularProgressIndicator(color: Colors.white))
          : wasteLogs.isEmpty
          ? Center(
        child: Text(
          'No waste data found.',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
      )
          : ListView.builder(
        itemCount: wasteLogs.length,
        itemBuilder: (context, index) {
          final log = wasteLogs[index];
          return Card(
            color: Colors.white.withOpacity(0.85),
            margin:
            EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Colors.green.shade800),
              title: Text(
                "Dry Waste: ${(log['dryWaste'] / 1000).toStringAsFixed(2)} kg\n"
                    "Moist Waste: ${(log['moistWaste'] / 1000).toStringAsFixed(2)} kg",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                formatTimestamp(log['timestamp']),
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
          );
        },
      ),
    );
  }
}