import 'dart:convert';

class MedicationItem {
  final String id;
  final String name;
  final List<String> times;
  final String createdAt;

  MedicationItem({
    required this.id,
    required this.name,
    required this.times,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'times': times,
        'createdAt': createdAt,
      };

  factory MedicationItem.fromJson(Map<String, dynamic> json) {
    return MedicationItem(
      id: json['id'],
      name: json['name'],
      times: List<String>.from(json['times'] ?? []),
      createdAt: json['createdAt'] ?? '2026-06-22',
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
      date: json['date'],
      pillId: json['pillId'],
      time: json['time'],
      isTaken: json['isTaken'],
    );
  }
}

class HospitalVisit {
  final String id;
  final String date;
  final String visitTime;
  final String morningAlarmTime;
  final String note;

  HospitalVisit({
    required this.id,
    required this.date,
    required this.visitTime,
    required this.morningAlarmTime,
    required this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'visitTime': visitTime,
        'morningAlarmTime': morningAlarmTime,
        'note': note,
      };

  factory HospitalVisit.fromJson(Map<String, dynamic> json) {
    return HospitalVisit(
      id: json['id'],
      date: json['date'],
      visitTime: json['visitTime'],
      morningAlarmTime: json['morningAlarmTime'],
      note: json['note'] ?? '',
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
      date: json['date'],
      steps: json['steps'],
      goal: json['goal'],
    );
  }
}
