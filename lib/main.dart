import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/api_session.dart';
import 'providers/category_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'screens/admin_screen.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await NotificationService.showFromMessage(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('th', null);
  if (!kIsWeb) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.init();
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ApiSession()..restore()),
        ChangeNotifierProxyProvider<ApiSession, CategoryProvider>(
          create: (context) => CategoryProvider(context.read<ApiSession>()),
          update: (_, session, provider) =>
              provider ?? CategoryProvider(session),
        ),
      ],
      child: const FarmerApp(),
    ),
  );
}

class FarmerApp extends StatelessWidget {
  const FarmerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'เกษตรกร',
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('th'), Locale('en')],
    locale: const Locale('th'),
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF168251),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF1F7F1),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF176B45),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Color(0xFFE3EEE7)),
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF176B45),
        elevation: 8,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? const Color(0xFF176B45)
                : const Color(0xFF596A60),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xFF596A60),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FCF9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0ECE4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0ECE4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF168251), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF168251),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF168251),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF168251),
          side: const BorderSide(color: Color(0xFF9BCDB1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE2F7E9),
        side: BorderSide.none,
        labelStyle: const TextStyle(color: Color(0xFF087342)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Color(0xFF168251),
        unselectedLabelColor: Color(0xFF81928A),
        indicatorColor: Color(0xFF168251),
      ),
      dialogTheme: DialogThemeData(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: Color(0xFF18352A),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    ),
    home: const AuthWrapper(),
  );
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  @override
  Widget build(BuildContext context) => Consumer<ApiSession>(
    builder: (context, session, _) {
      if (!session.initialized)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return session.isAuthenticated
          ? (session.user?.role == 'admin'
                ? const AdminScreen()
                : const MainScreen())
          : const AuthScreen();
    },
  );
}
