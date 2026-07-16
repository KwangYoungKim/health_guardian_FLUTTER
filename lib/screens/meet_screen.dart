import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/meet_repository.dart';

enum MeetState { lobby, creatingRoom, inRoom }

class MeetScreen extends StatefulWidget {
  final MeetRepository meetRepo;
  final String? initialRoomCode;
  final VoidCallback? onRoomJoined;

  const MeetScreen({
    Key? key,
    required this.meetRepo,
    this.initialRoomCode,
    this.onRoomJoined,
  }) : super(key: key);

  @override
  State<MeetScreen> createState() => _MeetScreenState();
}

class _MeetScreenState extends State<MeetScreen> {
  MeetState _meetState = MeetState.lobby;
  String _roomCode = "";
  LatLng? _destination;
  String _pendingMeetName = "";

  @override
  void initState() {
    super.initState();
    if (widget.initialRoomCode != null) {
      _joinRoom(widget.initialRoomCode!);
    }
  }

  void _joinRoom(String code) {
    setState(() {
      _roomCode = code;
    });
    widget.meetRepo.getRoomDestination(code, (dest) {
      if (dest != null) {
        setState(() {
          _destination = dest;
          _meetState = MeetState.inRoom;
        });
        if (widget.onRoomJoined != null) {
          widget.onRoomJoined!();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("방을 찾을 수 없거나 목적지가 없습니다."))
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String nickname = widget.meetRepo.getUserName();
    String displayNick = nickname.length > 10 ? nickname.substring(0, 10) : nickname;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "🤝 Meet (모임)",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF00E5FF),
          ),
        ),
        if (displayNick.isNotEmpty)
          Text(
            "👤 $displayNick",
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_meetState) {
      case MeetState.lobby:
        return LobbyView(
          meetRepo: widget.meetRepo,
          onCreateRoom: (name) {
            setState(() {
              _pendingMeetName = name;
              _meetState = MeetState.creatingRoom;
            });
          },
          onJoinRoom: _joinRoom,
        );
      case MeetState.creatingRoom:
        return CreateRoomView(
          onRoomCreated: (dest) {
            widget.meetRepo.createRoom(_pendingMeetName, dest, (newRoomCode) {
              if (newRoomCode != null) {
                setState(() {
                  _destination = dest;
                  _roomCode = newRoomCode;
                  _meetState = MeetState.inRoom;
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("방 생성 실패. 파이어베이스 연결을 확인해주세요."))
                );
              }
            });
          },
          onCancel: () {
            setState(() {
              _meetState = MeetState.lobby;
            });
          },
        );
      case MeetState.inRoom:
        if (_destination == null) return const Center(child: CircularProgressIndicator());
        return InRoomLiveMap(
          roomCode: _roomCode,
          initialDestination: _destination!,
          meetRepo: widget.meetRepo,
          onLeave: () {
            widget.meetRepo.setActiveRoomCode(null);
            setState(() {
              _meetState = MeetState.lobby;
            });
          },
        );
    }
  }
}

class LobbyView extends StatefulWidget {
  final MeetRepository meetRepo;
  final Function(String) onCreateRoom;
  final Function(String) onJoinRoom;

  const LobbyView({
    Key? key,
    required this.meetRepo,
    required this.onCreateRoom,
    required this.onJoinRoom,
  }) : super(key: key);

  @override
  State<LobbyView> createState() => _LobbyViewState();
}

class _LobbyViewState extends State<LobbyView> {
  final TextEditingController _meetNameController = TextEditingController();
  final TextEditingController _joinCodeController = TextEditingController();
  List<RoomInfo> _myMeets = [];
  StreamSubscription? _meetsSub;

  @override
  void initState() {
    super.initState();
    _meetsSub = widget.meetRepo.observeMyMeets().listen((rooms) {
      if (mounted) {
        setState(() {
          _myMeets = rooms;
        });
      }
    });
  }

  @override
  void dispose() {
    _meetsSub?.cancel();
    _meetNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Card(
                color: const Color(0x33FFFFFF),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text("새 모임 만들기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _meetNameController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Meet 명",
                          hintStyle: const TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: const Color(0x33FFFFFF),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          onPressed: () {
                            if (_meetNameController.text.trim().isNotEmpty) {
                              widget.onCreateRoom(_meetNameController.text.trim());
                            }
                          },
                          child: const Text("만들기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                color: const Color(0x33FFFFFF),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text("참여하기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _joinCodeController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "초대코드 입력",
                          hintStyle: const TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: const Color(0x33FFFFFF),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                          onPressed: () {
                            if (_joinCodeController.text.trim().isNotEmpty) {
                              widget.onJoinRoom(_joinCodeController.text.trim());
                            }
                          },
                          child: const Text("참여", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Card(
            color: const Color(0x3300E5FF),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Meet 이력", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _myMeets.length,
                      itemBuilder: (context, index) {
                        final room = _myMeets[index];
                        return _buildRoomItem(room);
                      },
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomItem(RoomInfo room) {
    String shortName = room.name.length > 8 ? "${room.name.substring(0, 8)}..." : room.name;
    bool isActive = room.status == "ACTIVE";

    return InkWell(
      onTap: () => widget.onJoinRoom(room.roomCode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Text(shortName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1),
                  if (room.isHost)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white70, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _showRenameDialog(room);
                      },
                    )
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Text("${room.memberCount}명", style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            if (room.isHost)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive ? const Color(0xFF5C6BC0) : const Color(0xFFD7CCC8),
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () {
                      widget.meetRepo.changeRoomStatus(room.roomCode, isActive ? "ENDED" : "ACTIVE");
                    },
                    child: Text(isActive ? "진행중" : "종료", style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 11)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey, size: 18),
                    onPressed: () => widget.meetRepo.deleteRoom(room.roomCode),
                  )
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF5C6BC0) : const Color(0xFFD7CCC8),
                      borderRadius: BorderRadius.circular(16)
                    ),
                    child: Text(isActive ? "진행중" : "종료", style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 11)),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: room.isParticipating ? const Color(0xFF00E5FF) : Colors.grey,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      widget.meetRepo.updateParticipationStatus(room.roomCode, !room.isParticipating);
                    },
                    child: Text(room.isParticipating ? "참여" : "불참", style: TextStyle(color: room.isParticipating ? Colors.black : Colors.white, fontSize: 11)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.exit_to_app, color: Colors.grey, size: 18),
                    onPressed: () => widget.meetRepo.deleteRoom(room.roomCode),
                  )
                ],
              )
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(RoomInfo room) {
    TextEditingController renameCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) {
      return AlertDialog(
        backgroundColor: const Color(0xFF2C3E50),
        title: const Text("모임명 변경", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: renameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "새로운 모임명을 입력하세요",
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0x33FFFFFF),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () {
            if (renameCtrl.text.trim().isNotEmpty) {
              widget.meetRepo.changeRoomName(room.roomCode, renameCtrl.text.trim());
            }
            Navigator.pop(ctx);
          }, child: const Text("저장", style: TextStyle(color: Color(0xFF00E5FF)))),
        ],
      );
    });
  }
}

class CreateRoomView extends StatefulWidget {
  final Function(LatLng) onRoomCreated;
  final VoidCallback onCancel;

  const CreateRoomView({Key? key, required this.onRoomCreated, required this.onCancel}) : super(key: key);

  @override
  State<CreateRoomView> createState() => _CreateRoomViewState();
}

class _CreateRoomViewState extends State<CreateRoomView> {
  LatLng? _tempDest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📍 목적지(모임 장소)를 지도에서 클릭해주세요.", style: TextStyle(color: Colors.white)),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(37.5665, 126.9780),
                initialZoom: 15.0,
                onTap: (tapPosition, point) {
                  setState(() {
                    _tempDest = point;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.healthguardian',
                ),
                if (_tempDest != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _tempDest!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: widget.onCancel,
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white)),
              child: const Text("취소", style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: _tempDest != null ? () => widget.onRoomCreated(_tempDest!) : null,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
              child: const Text("방 생성 및 초대코드 발급", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        )
      ],
    );
  }
}

class InRoomLiveMap extends StatefulWidget {
  final String roomCode;
  final LatLng initialDestination;
  final MeetRepository meetRepo;
  final VoidCallback onLeave;

  const InRoomLiveMap({
    Key? key,
    required this.roomCode,
    required this.initialDestination,
    required this.meetRepo,
    required this.onLeave,
  }) : super(key: key);

  @override
  State<InRoomLiveMap> createState() => _InRoomLiveMapState();
}

class _InRoomLiveMapState extends State<InRoomLiveMap> {
  List<MeetMember> _members = [];
  late LatLng _destination;
  bool _isHost = false;
  bool _isEditingDestination = false;
  LatLng? _tempDestination;
  String _roomStatus = "ACTIVE";

  StreamSubscription? _statusSub;
  StreamSubscription? _destSub;
  StreamSubscription? _membersSub;
  StreamSubscription<Position>? _locSub;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
    _statusSub = widget.meetRepo.observeRoomStatus(widget.roomCode).listen((status) {
      if (mounted) setState(() => _roomStatus = status);
    });

    widget.meetRepo.isHost(widget.roomCode, (host) {
      if (mounted) setState(() => _isHost = host);
    });

    _destSub = widget.meetRepo.observeDestination(widget.roomCode).listen((newDest) {
      if (!mounted) return;
      if (newDest == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("방이 삭제되었습니다.")));
        widget.onLeave();
      } else {
        setState(() => _destination = newDest);
      }
    });

    _membersSub = widget.meetRepo.joinRoom(widget.roomCode).listen((newMembers) {
      if (mounted) setState(() => _members = newMembers);
    });

    _startLocationUpdates();
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _locSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    )).listen((Position position) {
      if (_roomStatus == "ACTIVE") {
        widget.meetRepo.updateLocation(widget.roomCode, LatLng(position.latitude, position.longitude));
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _destSub?.cancel();
    _membersSub?.cancel();
    _locSub?.cancel();
    super.dispose();
  }

  void _showInviteDialog() {
    widget.meetRepo.fetchUsers((usersList) {
      showDialog(context: context, builder: (ctx) {
        return AlertDialog(
          title: const Text("누구를 초대할까요?"),
          content: SizedBox(
            width: double.maxFinite,
            child: usersList.isEmpty
                ? const Text("초대할 수 있는 사용자를 불러오는 중이거나 아직 가입한 다른 사용자가 없습니다.")
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: usersList.length,
                    itemBuilder: (context, index) {
                      final user = usersList[index];
                      return ListTile(
                        leading: const Icon(Icons.person_add, color: Color(0xFF00E5FF)),
                        title: Text(user['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("ID: ${user['id']?.substring(0, 8)}...", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        onTap: () {
                          widget.meetRepo.sendInvite(user['id']!, widget.roomCode);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${user['name']}님에게 초대 알림을 보냈습니다.")));
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기")),
          ],
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Marker> markers = [];
    List<Polyline> polylines = [];

    markers.add(Marker(
      point: _tempDestination ?? _destination,
      width: 40,
      height: 40,
      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
    ));

    for (var member in _members) {
      if (!member.isParticipating) continue;

      if (member.path.isNotEmpty) {
        polylines.add(Polyline(
          points: member.path,
          color: Color(member.color).withOpacity(0.8),
          strokeWidth: 5.0,
        ));
      }

      if (member.location.latitude != 0.0 || member.location.longitude != 0.0) {
        bool isMe = member.id == widget.meetRepo.getCurrentUserId();
        String displayStr = isMe ? "${member.name} (나)" : member.name;
        
        markers.add(Marker(
          point: member.location,
          width: 80,
          height: 60,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(displayStr, style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
              Icon(Icons.person_pin_circle, color: Color(member.color), size: 30),
            ],
          ),
        ));
      }
    }

    return Column(
      children: [
        Card(
          color: const Color(0x3300E5FF),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.roomCode));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("초대 코드가 복사되었습니다.")));
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("초대 코드 (터치하여 복사)", style: TextStyle(color: Colors.grey, fontSize: 10)),
                        Row(
                          children: [
                            Text(widget.roomCode, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            const Icon(Icons.copy, color: Colors.white, size: 16),
                          ],
                        ),
                        if (_isHost && _isEditingDestination)
                          const Padding(
                            padding: EdgeInsets.only(top: 4.0),
                            child: Text("지도에서 새 목적지를 클릭하세요", style: TextStyle(color: Colors.yellow, fontSize: 12)),
                          )
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.person_add, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
                      onPressed: _showInviteDialog,
                    ),
                    const SizedBox(width: 8),
                    if (_isHost)
                      if (_isEditingDestination) ...[
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          style: IconButton.styleFrom(backgroundColor: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _isEditingDestination = false;
                              _tempDestination = null;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.black),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                          onPressed: _tempDestination == null ? null : () {
                            widget.meetRepo.updateDestination(widget.roomCode, _tempDestination!);
                            setState(() {
                              _isEditingDestination = false;
                              _tempDestination = null;
                            });
                          },
                        ),
                      ] else ...[
                        IconButton(
                          icon: const Icon(Icons.edit_location, color: Colors.black),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                          onPressed: () {
                            setState(() {
                              _isEditingDestination = true;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
                          onPressed: () => widget.meetRepo.deleteRoom(widget.roomCode),
                        ),
                      ],
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.exit_to_app, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
                      onPressed: widget.onLeave,
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _destination,
                initialZoom: 14.0,
                onTap: (tapPosition, point) {
                  if (_isEditingDestination) {
                    setState(() {
                      _tempDestination = point;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.healthguardian',
                ),
                PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0x22FFFFFF),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("참여자 목록 (${_members.length}명)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final m = _members[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: Column(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(m.color),
                              radius: 16,
                              child: Text(m.name.isNotEmpty ? m.name[0] : "?", style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.name.length > 5 ? m.name.substring(0, 5) : m.name,
                              style: TextStyle(
                                color: m.isParticipating ? Colors.white : Colors.grey,
                                fontSize: 10,
                                decoration: m.isParticipating ? null : TextDecoration.lineThrough
                              )
                            )
                          ],
                        ),
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
  }
}
