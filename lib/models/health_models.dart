

import 'dart:convert';

class MedicationItem {
  final String id;
  final String name;
  final List<String> times;
  final String createdAt;
  final String ringtoneUri;

  MedicationItem({
    required this.id,
    required this.name,
    required this.times,
    required this.createdAt,
    this.ringtoneUri = 'default',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'times': times,
        'createdAt': createdAt,
        'ringtoneUri': ringtoneUri,
      };

  factory MedicationItem.fromJson(Map<String, dynamic> json) {
    return MedicationItem(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      times: json['times'] is List ? List<String>.from(json['times'].map((e) => e.toString())) : [],
      createdAt: json['createdAt'] as String? ?? '2026-06-22',
      ringtoneUri: json['ringtoneUri'] as String? ?? 'default',
    );
  }
}

class MedicationLog {
  final String date;
  final String pillId;
  final String time;
  final bool isTaken;

  MedicationLog({
    required this.date,
    required this.pillId,
    required this.time,
    required this.isTaken,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'pillId': pillId,
        'time': time,
        'isTaken': isTaken,
      };

  factory MedicationLog.fromJson(Map<String, dynamic> json) {
    return MedicationLog(
      date: json['date'] as String? ?? '',
      pillId: json['pillId']?.toString() ?? '',
      time: json['time'] as String? ?? '',
      isTaken: json['isTaken'] is String ? json['isTaken'] == 'true' : (json['isTaken'] as bool? ?? false),
    );
  }
}

class HospitalVisit {
  final String id;
  final String date;
  final String visitTime;
  final String morningAlarmTime;
  final String note;
  final String ringtoneUri;

  HospitalVisit({
    required this.id,
    required this.date,
    required this.visitTime,
    required this.morningAlarmTime,
    required this.note,
    this.ringtoneUri = 'default',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'visitTime': visitTime,
        'morningAlarmTime': morningAlarmTime,
        'note': note,
        'ringtoneUri': ringtoneUri,
      };

  factory HospitalVisit.fromJson(Map<String, dynamic> json) {
    return HospitalVisit(
      id: json['id']?.toString() ?? '',
      date: json['date'] as String? ?? '',
      visitTime: json['visitTime'] as String? ?? '',
      morningAlarmTime: json['morningAlarmTime'] as String? ?? '',
      note: json['note'] as String? ?? '',
      ringtoneUri: json['ringtoneUri'] as String? ?? 'default',
    );
  }
}

class StepData {
  final String date;
  final int steps;
  final int goal;

  StepData({
    required this.date,
    required this.steps,
    required this.goal,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'steps': steps,
        'goal': goal,
      };

  factory StepData.fromJson(Map<String, dynamic> json) {
    return StepData(
      date: json['date'] as String? ?? '',
      steps: json['steps'] is String ? (int.tryParse(json['steps']) ?? 0) : ((json['steps'] as num?)?.toInt() ?? 0),
      goal: json['goal'] is String ? (int.tryParse(json['goal']) ?? 0) : ((json['goal'] as num?)?.toInt() ?? 0),
    );
  }
}

class PathPoint {
  final double lat;
  final double lng;
  final int timestamp;

  PathPoint({
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp,
      };

  factory PathPoint.fromJson(Map<String, dynamic> json) {
    return PathPoint(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocationMemo {
  final int id;
  final String date;
  final double lat;
  final double lng;
  final String memo;
  final String time;

  LocationMemo({
    required this.id,
    required this.date,
    required this.lat,
    required this.lng,
    required this.memo,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'lat': lat,
        'lng': lng,
        'memo': memo,
        'time': time,
      };

  factory LocationMemo.fromJson(Map<String, dynamic> json) {
    return LocationMemo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      date: json['date'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      memo: json['memo'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }
}

class DailyPath {
  final String id;
  final String userId;
  final String date;
  final String pathJson;

  DailyPath({
    required this.id,
    required this.userId,
    required this.date,
    required this.pathJson,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'date': date,
        'pathJson': pathJson,
      };

  factory DailyPath.fromJson(Map<String, dynamic> json) {
    String pJson = '[]';
    if (json['pathJson'] != null) {
      if (json['pathJson'] is String) {
        pJson = json['pathJson'];
      } else {
        try {
          pJson = jsonEncode(json['pathJson']);
        } catch (_) {}
      }
    }
    return DailyPath(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      date: json['date'] as String? ?? '',
      pathJson: pJson,
    );
  }
}
