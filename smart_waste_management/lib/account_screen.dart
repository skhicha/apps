import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class AccountScreen extends StatefulWidget {
  @override
  _AccountScreenState createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, String> userData = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  void _fetchUserData() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists && userDoc.data() != null) {
          var data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            userData = {
              "Full Name": data["name"] ?? "N/A",
              "Date of Birth": data["dob"] ?? "N/A",
              "Gender": data["gender"] ?? "N/A",
              "State": data["state"] ?? "N/A",
              "City": data["city"] ?? "N/A",
              "Email": data["email"] ?? "N/A",
            };
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = "User data not found!";
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = "No user logged in!";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error fetching data: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  void _signOut() async {
    try {
      await _auth.signOut();
      Fluttertoast.showToast(msg: "Signed out successfully!", backgroundColor: Colors.green);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginScreen()),
            (route) => false,
      );
    } catch (e) {
      Fluttertoast.showToast(msg: "Error signing out: ${e.toString()}", backgroundColor: Colors.red);
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
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.black),
            onPressed: _signOut,
            tooltip: "Sign Out",
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/backgrounds/account_bg.jpg"),
            fit: BoxFit.cover,
          ),
        ),
        padding: EdgeInsets.only(top: kToolbarHeight + 40),
        child: Center(
          child: _isLoading
              ? CircularProgressIndicator(color: Colors.white)
              : _errorMessage != null
              ? Text(_errorMessage!, style: TextStyle(color: Colors.white, fontSize: 18))
              : Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                // ⬇️ Enhanced Visibility for "Account Details"
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Account Details",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 5.0,
                          color: Colors.black87,
                          offset: Offset(1.5, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),

                Expanded(
                  child: ListView(
                    children: userData.entries.map((entry) {
                      return Card(
                        elevation: 5,
                        color: Colors.white.withOpacity(0.9),
                        margin: EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          title: Text(entry.key, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          subtitle: Text(entry.value, style: TextStyle(fontSize: 16)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _signOut,
                  icon: Icon(Icons.exit_to_app, color: Colors.white),
                  label: Text("Sign Out", style: TextStyle(fontSize: 18, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    shape: StadiumBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}