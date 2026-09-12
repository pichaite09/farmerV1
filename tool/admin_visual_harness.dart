import 'package:flutter/material.dart';
import 'package:farmer/screens/admin_screen.dart';
import '../test/support/admin_fixture_api.dart';

// Separate verification target: never compile this entrypoint for production.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      theme: ThemeData.light(),
      home: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber,
            padding: const EdgeInsets.all(4),
            child: const Text(
              'SYNTHETIC UI FIXTURES • NOT LIVE DATA',
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black, fontSize: 12),
            ),
          ),
          Expanded(
            child: AdminScreen(
              api: AdminFixtureApi(),
              currentUserId: 'synthetic-admin',
            ),
          ),
        ],
      ),
    ),
  );
}
