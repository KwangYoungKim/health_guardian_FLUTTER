import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/alarm_screen.dart';
import 'screens/medication_screen.dart';
import 'screens/hospital_screen.dart';
import 'screens/walking_screen.dart';
import 'screens/memo_screen.dart';
import 'screens/meet_screen.dart';
import 'screens/restore_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/register_screen.dart';
import 'services/meet_repository.dart';

import 'services/health_repository.dart';
import 'services/notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko', null);
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyAFX5AcDzSReETQBPLDxs12K7S4DxAId54',
        appId: '1:657804463211:ios:b01e3bd3c3add2d920f52e',
        messagingSenderId: '657804463211',
        projectId: 'meetapp-47291',
        databaseURL: 'https://meetapp-47291-default-rtdb.firebaseio.com',
      ),
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  await HealthRepository.instance.init();
  await MeetRepository.instance.init();
  await NotificationService.instance.init();
  
  runApp(const HealthGuardianApp());
}

class HealthGuardianApp extends StatelessWidget {
  const HealthGuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Guardian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF00E5FF),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          surface: Color(0x33FFFFFF),
          onSurface: Colors.white,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1E293B),
          contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
          actionTextColor: Color(0xFF00E5FF),
        ),
      ),
      home: FutureBuilder<String?>(
        future: SharedPreferences.getInstance().then((prefs) => prefs.getString('api_user_id')),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F172A),
              body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
            );
          }
          if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
            return const MainScreen();
          }
          return const RegisterScreen();
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _screens = [
    const AlarmScreen(),
    const MedicationScreen(),
    const HospitalScreen(),
    const WalkingScreen(),
    const MemoScreen(),
    MeetScreen(meetRepo: MeetRepository.instance),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              _screens[_selectedIndex],
            ],
          ),
        ),
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: const Color(0xFF1E293B),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF00E5FF),
          unselectedItemColor: Colors.grey,
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Text("⏳", style: TextStyle(fontSize: 20)), label: '알람'),
            BottomNavigationBarItem(icon: Text("💊", style: TextStyle(fontSize: 20)), label: '약 복용'),
            BottomNavigationBarItem(icon: Text("🏥", style: TextStyle(fontSize: 20)), label: '병원'),
            BottomNavigationBarItem(icon: Text("👟", style: TextStyle(fontSize: 20)), label: '걷기'),
            BottomNavigationBarItem(icon: Text("📝", style: TextStyle(fontSize: 20)), label: '메모'),
            BottomNavigationBarItem(icon: Text("🤝", style: TextStyle(fontSize: 20)), label: 'Meet'),
            BottomNavigationBarItem(icon: Text("⚙️", style: TextStyle(fontSize: 20)), label: '설정'),
          ],
        ),
      ),
    );
  }
}

