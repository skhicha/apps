import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'dashboard_screen.dart';
import 'bmc_screen.dart';
import 'waste_history_screen.dart';
import 'account_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(); // ✅ Ensure Firebase is initialized
  } catch (e) {
    print("Firebase initialization error: $e"); // ✅ Log errors if Firebase fails
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Waste Management',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      initialRoute: '/',  // ✅ Define routes properly
      routes: {
        '/': (context) => LoginScreen(),
        '/signup': (context) => SignupScreen(),
        '/dashboard': (context) => DashboardScreen(),
        '/bmc': (context) => BmcScreen(),
        '/waste-history': (context) => WasteHistoryScreen(),
        '/account': (context) => AccountScreen(),
      },
    );
  }
}