import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/health_models.dart';
import 'api_service.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundLocationService {
  static final BackgroundLocationService instance = BackgroundLocationService._internal();
  BackgroundLocationService._internal();

  Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // ⚡ Create Android Notification Channel to prevent Bad notification crash on Android 13/14/15/16
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'smart_health_location_service',
      '24시간 무중단 동선 추적 서비스',
      description: '백그라운드에서 실시간 위치를 안전하게 기록합니다.',
      importance: Importance.low,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStartBackground,
        autoStart: true,
        isForegroundMode: true,
        autoStartOnBoot: true,
        notificationChannelId: 'smart_health_location_service',
        initialNotificationTitle: "👟 Smart Health 24시간 무중단 동선 추적",
        initialNotificationContent: "앱이 종료되어도 백그라운드에서 실시간 이동 경로가 자동 수집됩니다.",
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStartBackground,
        onBackground: onIosBackground,
      ),
    );

    await service.startService();
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStartBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  LocationSettings locationSettings;
  if (defaultTargetPlatform == TargetPlatform.android) {
    locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: "👟 Smart Health 24시간 무중단 동선 추적",
        notificationText: "앱이 종료되어도 백그라운드에서 실시간 이동 경로가 자동 수집됩니다.",
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        enableWakeLock: true,
      ),
    );
  } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
    locationSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    );
  } else {
    locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );
  }

  Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
    // 1. Ignore coarse GPS noise (indoor jitter > 30m accuracy)
    if (position.accuracy > 30) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final nowMs = position.timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;

    // Load daily path from SharedPreferences
    final String? jsonString = prefs.getString("path_$today");
    List<PathPoint> path = [];
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        path = jsonList.map((e) => PathPoint.fromJson(e)).toList();
      } catch (_) {}
    }

    if (path.isNotEmpty) {
      final lastPoint = path.last;
      if (lastPoint.lat != 0.0 && lastPoint.lng != 0.0) {
        final timeDiffSec = (nowMs - lastPoint.timestamp) / 1000.0;
        final dist = Geolocator.distanceBetween(
          lastPoint.lat, lastPoint.lng,
          position.latitude, position.longitude,
        );
        // ⚡ 2. Stationary Filter: Completely ignore stationary jitter (less than 2.0m movement within 5 minutes)
        if (dist < 2.0 && timeDiffSec < 300) return;
        // ⚡ 3. Glitch Rejection: Reject teleport spikes (>500m in <30s)
        if (dist > 500 && timeDiffSec < 30) return;
      }
    }

    path.add(PathPoint(
      lat: position.latitude,
      lng: position.longitude,
      timestamp: nowMs,
    ));

    final newJsonString = jsonEncode(path.map((e) => e.toJson()).toList());
    await prefs.setString("path_$today", newJsonString);

    // Sync to PostgreSQL backend DBMS asynchronously
    final userId = prefs.getString('api_user_id');
    if (userId != null) {
      final dailyPath = DailyPath(
        id: "${userId}_$today",
        userId: userId,
        date: today,
        pathJson: newJsonString,
      );
      ApiService.syncPaths(userId, [dailyPath.toJson()]).catchError((_) {});
    }

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(
          title: "👟 Smart Health 24시간 무중단 동선 추적",
          content: "위치: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)} (자동 기록 중)",
        );
      }
    }
  });
}
