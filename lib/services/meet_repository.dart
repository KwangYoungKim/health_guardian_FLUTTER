import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class RoomInfo {
  final String roomCode;
  final String name;
  final double destLat;
  final double destLon;
  final int memberCount;
  final String status;
  final bool isHost;
  final bool isParticipating;
  final int createdAt;

  RoomInfo({
    required this.roomCode,
    required this.name,
    required this.destLat,
    required this.destLon,
    required this.memberCount,
    required this.status,
    required this.isHost,
    required this.isParticipating,
    required this.createdAt,
  });
}

class MeetMember {
  final String id;
  final String name;
  final LatLng location;
  final int color;
  final List<LatLng> path;
  final bool isParticipating;

  MeetMember({
    required this.id,
    required this.name,
    required this.location,
    required this.color,
    this.path = const [],
    this.isParticipating = true,
  });
}

class MeetRepository {
  static final MeetRepository instance = MeetRepository._internal();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  late SharedPreferences _prefs;
  late String _sessionId;
  bool _initialized = false;

  MeetRepository._internal();

  final List<int> _colors = [
    0xFF00E5FF, 0xFFFF4081, 0xFFFFC107, 
    0xFF4CAF50, 0xFF9C27B0, 0xFFFF5722
  ];

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    String? existingId = _prefs.getString('session_id');
    if (existingId != null) {
      _sessionId = existingId;
    } else {
      _sessionId = const Uuid().v4();
      await _prefs.setString('session_id', _sessionId);
    }
    _initialized = true;
  }

  String? getCurrentUserId() {
    return getUserId();
  }

  String getUserId() {
    return _prefs.getString('api_user_id') ?? _prefs.getString('uuid') ?? _sessionId;
  }

  String? getActiveRoomCode() {
    return _prefs.getString('active_room_code');
  }

  Future<void> setActiveRoomCode(String? roomCode) async {
    if (roomCode == null) {
      await _prefs.remove('active_room_code');
    } else {
      await _prefs.setString('active_room_code', roomCode);
    }
  }

  List<String> getParticipatingRooms() {
    return _prefs.getStringList('participating_rooms') ?? [];
  }

  Future<void> setParticipatingRoom(String roomCode, bool isParticipating) async {
    List<String> current = getParticipatingRooms().toList();
    if (isParticipating) {
      if (!current.contains(roomCode)) current.add(roomCode);
    } else {
      current.remove(roomCode);
    }
    await _prefs.setStringList('participating_rooms', current);
  }

  Future<void> saveUserId(String id) async {
    await _prefs.setString('uuid', id);
  }

  bool hasProfile() {
    return _prefs.getString('user_name') != null;
  }

  String getUserName() {
    return _prefs.getString('api_nickname') ?? _prefs.getString('user_name') ?? "User_${_sessionId.substring(0, 4)}";
  }

  Future<void> setUserName(String name) async {
    await _prefs.setString('api_nickname', name);
    await _prefs.setString('user_name', name);
    await _database.ref().child("users").child(getUserId()).child("name").set(name);
  }

  void listenForInvites(Function(String) onInviteReceived) {
    _database.ref().child("users").child(getUserId()).child("invites").onValue.listen((event) {
      final snapshot = event.snapshot;
      if (snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          if (value is String) {
            onInviteReceived(value);
            _database.ref().child("users").child(getUserId()).child("invites").child(key).remove();
          }
        });
      }
    });
  }

  Future<void> sendInvite(String targetUuid, String roomCode) async {
    await _database.ref().child("users").child(targetUuid).child("invites").push().set(roomCode);
  }

  Future<void> fetchUsers(Function(List<Map<String, String>>) onUsersFetched) async {
    final event = await _database.ref().child("users").once();
    final snapshot = event.snapshot;
    List<Map<String, String>> users = [];
    if (snapshot.value != null) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        if (value is Map && key != getUserId()) {
          final name = value['name'] as String?;
          if (name != null) {
            users.add({'id': key.toString(), 'name': name});
          }
        }
      });
    }
    
    final seen = <String>{};
    final distinctUsers = users.where((u) => seen.add(u['name']!.toLowerCase())).toList();
    onUsersFetched(distinctUsers);
  }

  Future<List<MeetMember>> getRoomMembersOnce(String roomCode) async {
    try {
      final event = await _database.ref().child("meets").child(roomCode).child("members").once();
      final snapshot = event.snapshot;
      List<MeetMember> memberList = [];
      if (snapshot.exists && snapshot.value is Map) {
        final data = snapshot.value as Map;
        data.forEach((key, value) {
          if (value is Map) {
            try {
              final id = value['id']?.toString();
              if (id == null) return;
              final name = value['name']?.toString() ?? "Unknown";
              final lat = (value['lat'] as num?)?.toDouble();
              final lon = (value['lon'] as num?)?.toDouble();
              if (lat == null || lon == null) return;
              final color = (value['color'] as num?)?.toInt() ?? 0xFF00E5FF;
              
              List<LatLng> pathList = [];
              if (value['path'] is Map) {
                final pathMap = value['path'] as Map;
                final sortedKeys = pathMap.keys.map((k) => k.toString()).toList()..sort();
                for (var pKey in sortedKeys) {
                  final pVal = pathMap[pKey];
                  if (pVal is Map) {
                    final pLat = (pVal['lat'] as num?)?.toDouble();
                    final pLon = (pVal['lon'] as num?)?.toDouble();
                    if (pLat != null && pLon != null) {
                      pathList.add(LatLng(pLat, pLon));
                    }
                  }
                }
              }
              final isParticipating = value['isParticipating'] == true || value['isParticipating'] == null;

              memberList.add(MeetMember(
                id: id,
                name: name,
                location: LatLng(lat, lon),
                color: color,
                path: pathList,
                isParticipating: isParticipating
              ));
            } catch (_) {}
          }
        });
      }
      return memberList;
    } catch (e) {
      print("Error in getRoomMembersOnce: $e");
      return [];
    }
  }

  Future<void> createRoom(String name, LatLng destination, Function(String?) onComplete) async {
    final hostId = getCurrentUserId();
    if (hostId == null) {
      onComplete(null);
      return;
    }
    final roomCode = "MEET-${Random().nextInt(9000) + 1000}";
    
    final roomData = {
      "name": name,
      "status": "ACTIVE",
      "destLat": destination.latitude,
      "destLon": destination.longitude,
      "hostId": hostId,
      "createdAt": DateTime.now().millisecondsSinceEpoch,
    };

    try {
      await _database.ref().child("meets").child(roomCode).set(roomData);
      
      final memberData = {
        "id": hostId,
        "name": getUserName(),
        "lat": 0.0,
        "lon": 0.0,
        "color": _colors[Random().nextInt(_colors.length)],
        "isParticipating": true
      };
      
      await _database.ref().child("meets").child(roomCode).child("members").child(hostId).set(memberData);
      await setActiveRoomCode(roomCode);
      await setParticipatingRoom(roomCode, true);
      onComplete(roomCode);
    } catch (e) {
      onComplete(null);
    }
  }

  Stream<List<MeetMember>> joinRoom(String roomCode) {
    final myId = getCurrentUserId();
    if (myId == null) return const Stream.empty();

    setActiveRoomCode(roomCode);

    final membersRef = _database.ref().child("meets").child(roomCode).child("members");

    return membersRef.onValue.map((event) {
      final snapshot = event.snapshot;
      List<MeetMember> memberList = [];
      
      if (snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        if (!data.containsKey(myId)) {
          final memberData = {
            "id": myId,
            "name": getUserName(),
            "lat": 0.0,
            "lon": 0.0,
            "color": _colors[Random().nextInt(_colors.length)],
            "isParticipating": true
          };
          membersRef.child(myId).set(memberData);
          setParticipatingRoom(roomCode, true);
        }

        data.forEach((key, value) {
          if (value is Map) {
            try {
              final id = value['id']?.toString();
              if (id == null) return;
              final name = value['name']?.toString() ?? "Unknown";
              final lat = (value['lat'] as num?)?.toDouble();
              final lon = (value['lon'] as num?)?.toDouble();
              if (lat == null || lon == null) return;
              final color = (value['color'] as num?)?.toInt() ?? 0xFF00E5FF;
              
              List<LatLng> pathList = [];
              if (value['path'] is Map) {
                final pathMap = value['path'] as Map;
                final sortedKeys = pathMap.keys.map((k) => k.toString()).toList()..sort();
                for (var pKey in sortedKeys) {
                  final pVal = pathMap[pKey];
                  if (pVal is Map) {
                    final pLat = (pVal['lat'] as num?)?.toDouble();
                    final pLon = (pVal['lon'] as num?)?.toDouble();
                    if (pLat != null && pLon != null) {
                      pathList.add(LatLng(pLat, pLon));
                    }
                  }
                }
              }

              final isParticipating = value['isParticipating'] == true || value['isParticipating'] == null;

              memberList.add(MeetMember(
                id: id,
                name: name,
                location: LatLng(lat, lon),
                color: color,
                path: pathList,
                isParticipating: isParticipating
              ));
            } catch (e) {
              // Ignore parsing errors for individual members
            }
          }
        });
      }
      return memberList;
    });
  }

  Future<void> updateLocation(String roomCode, LatLng location) async {
    final myId = getCurrentUserId();
    if (myId == null) return;
    if (location.latitude == 0.0 && location.longitude == 0.0) return;

    final myRef = _database.ref().child("meets").child(roomCode).child("members").child(myId);

    final updates = {
      "id": myId,
      "name": getUserName(),
      "lat": location.latitude,
      "lon": location.longitude
    };

    await myRef.update(updates);
    
    final colorSnapshot = await myRef.child("color").get();
    if (!colorSnapshot.exists) {
      await myRef.child("color").set(_colors[Random().nextInt(_colors.length)]);
    }

    // Check last path point to avoid duplicate zero-distance entries
    final lastPathSnap = await myRef.child("path").limitToLast(1).get();
    if (lastPathSnap.exists && lastPathSnap.value is Map) {
      final lastMap = (lastPathSnap.value as Map).values.first;
      if (lastMap is Map) {
        final lastLat = (lastMap['lat'] as num?)?.toDouble();
        final lastLon = (lastMap['lon'] as num?)?.toDouble();
        if (lastLat != null && lastLon != null) {
          final dist = Geolocator.distanceBetween(lastLat, lastLon, location.latitude, location.longitude);
          if (dist < 1.5) return; // Skip pushing if user hasn't moved 1.5 meters
        }
      }
    }

    final pathUpdates = {
      "lat": location.latitude,
      "lon": location.longitude,
      "ts": DateTime.now().millisecondsSinceEpoch
    };
    await myRef.child("path").push().set(pathUpdates);
  }

  Future<void> getRoomDestination(String roomCode, Function(LatLng?) onComplete) async {
    final snapshot = await _database.ref().child("meets").child(roomCode).get();
    if (snapshot.exists && snapshot.value is Map) {
      final data = snapshot.value as Map;
      final lat = (data['destLat'] as num?)?.toDouble();
      final lon = (data['destLon'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        onComplete(LatLng(lat, lon));
        return;
      }
    }
    onComplete(null);
  }

  Future<void> isHost(String roomCode, Function(bool) onComplete) async {
    final myId = getCurrentUserId();
    if (myId == null) {
      onComplete(false);
      return;
    }
    final snapshot = await _database.ref().child("meets").child(roomCode).child("hostId").get();
    if (snapshot.exists) {
      final hostId = snapshot.value?.toString().trim();
      onComplete(myId.trim() == hostId);
    } else {
      onComplete(false);
    }
  }

  Future<void> updateDestination(String roomCode, LatLng destination) async {
    final updates = {
      "destLat": destination.latitude,
      "destLon": destination.longitude
    };
    await _database.ref().child("meets").child(roomCode).update(updates);
  }

  Future<void> updateRoomDetails(String roomCode, String name, LatLng destination) async {
    final updates = {
      "name": name,
      "destLat": destination.latitude,
      "destLon": destination.longitude
    };
    await _database.ref().child("meets").child(roomCode).update(updates);
  }

  Future<void> deleteRoom(String roomCode) async {
    final myId = getCurrentUserId();
    if (myId == null) return;

    try {
      await _database.ref().child("meets").child(roomCode).set(null);
      await _database.ref().child("meets").child(roomCode).remove();
    } catch (e) {
      // Ignore if node already removed
    }

    final active = getActiveRoomCode();
    if (active == roomCode) {
      await setActiveRoomCode(null);
    }
    await setParticipatingRoom(roomCode, false);
  }

  Stream<LatLng?> observeDestination(String roomCode) {
    return _database.ref().child("meets").child(roomCode).onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null) return null;
      final data = snapshot.value as Map;
      final lat = (data['destLat'] as num?)?.toDouble();
      final lon = (data['destLon'] as num?)?.toDouble();
      if (lat != null && lon != null) {
        return LatLng(lat, lon);
      }
      return null;
    });
  }

  Future<void> changeRoomStatus(String roomCode, String newStatus) async {
    await _database.ref().child("meets").child(roomCode).child("status").set(newStatus);
  }

  Future<void> changeRoomName(String roomCode, String newName) async {
    await _database.ref().child("meets").child(roomCode).child("name").set(newName);
  }

  Stream<String> observeRoomStatus(String roomCode) {
    return _database.ref().child("meets").child(roomCode).child("status").onValue.map((event) {
      return event.snapshot.value?.toString() ?? "ACTIVE";
    });
  }

  Future<void> updateParticipationStatus(String roomCode, bool isParticipating) async {
    final myId = getCurrentUserId();
    if (myId == null) return;
    await _database.ref().child("meets").child(roomCode).child("members").child(myId).child("isParticipating").set(isParticipating);
    await setParticipatingRoom(roomCode, isParticipating);
  }

  Stream<List<RoomInfo>> observeMyMeets() {
    final myId = getCurrentUserId();
    if (myId == null) return const Stream.empty();
    final cleanMyId = myId.trim();

    return _database.ref().child("meets").onValue.map((event) {
      final snapshot = event.snapshot;
      List<RoomInfo> rooms = [];
      if (snapshot.value != null && snapshot.value is Map) {
        final data = snapshot.value as Map;
        data.forEach((roomCode, childVal) {
          if (childVal is Map) {
            final hostId = childVal['hostId']?.toString().trim();
            final membersSnapshot = childVal['members'] as Map?;
            
            bool isHost = (hostId != null && hostId == cleanMyId);
            bool isMember = (membersSnapshot != null && (membersSnapshot.containsKey(cleanMyId) || membersSnapshot.containsKey(myId)));

            if (isHost || isMember) {
              final name = childVal['name']?.toString() ?? "이름 없음";
              final status = childVal['status']?.toString() ?? "ACTIVE";
              final lat = (childVal['destLat'] as num?)?.toDouble() ?? 0.0;
              final lon = (childVal['destLon'] as num?)?.toDouble() ?? 0.0;
              final memberCount = membersSnapshot?.length ?? 0;
              
              bool isParticipating = true;
              if (isMember && membersSnapshot != null) {
                final myMemberData = (membersSnapshot[cleanMyId] ?? membersSnapshot[myId]) as Map?;
                if (myMemberData != null) {
                  isParticipating = myMemberData['isParticipating'] == true || myMemberData['isParticipating'] == null;
                }
              }

              final createdAt = (childVal['createdAt'] as num?)?.toInt() ?? 0;

              rooms.add(RoomInfo(
                roomCode: roomCode.toString(),
                name: name,
                destLat: lat,
                destLon: lon,
                memberCount: memberCount,
                status: status,
                isHost: isHost,
                isParticipating: isParticipating,
                createdAt: createdAt
              ));
            }
          }
        });
      }
      rooms.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return rooms;
    });
  }
}
