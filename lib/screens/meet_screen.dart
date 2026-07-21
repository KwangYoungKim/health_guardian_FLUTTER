import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/meet_repository.dart';

Widget buildSleekFlagMarker({String label = "목적지"}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF1744), Color(0xFFC62828)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
          ],
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tour, color: Color(0xFFFFD700), size: 13),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: -0.2),
            ),
          ],
        ),
      ),
      Container(
        width: 2.5,
        height: 9,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 2)],
        ),
      ),
      Container(
        width: 7,
        height: 3,
        decoration: BoxDecoration(
          color: Colors.white70,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ],
  );
}

enum MeetState { lobby, creatingRoom, editingRoom, inRoom }

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

  // Edit mode fields
  String _editingRoomCode = "";
  String _editingRoomName = "";
  LatLng? _editingDestination;

  @override
  void initState() {
    super.initState();
    if (widget.initialRoomCode != null) {
      _joinRoom(widget.initialRoomCode!);
    }
  }

  void _startEditingRoom(RoomInfo room) {
    setState(() {
      _editingRoomCode = room.roomCode;
      _editingRoomName = room.name;
      _editingDestination = LatLng(room.destLat, room.destLon);
      _meetState = MeetState.editingRoom;
    });
  }

  void _startEditingRoomFromCode(String code, String name, LatLng dest) {
    setState(() {
      _editingRoomCode = code;
      _editingRoomName = name;
      _editingDestination = dest;
      _meetState = MeetState.editingRoom;
    });
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
          onEditRoom: _startEditingRoom,
        );
      case MeetState.creatingRoom:
        return CreateOrEditRoomView(
          isEditing: false,
          initialName: _pendingMeetName,
          meetRepo: widget.meetRepo,
          onSave: (name, dest) {
            widget.meetRepo.createRoom(name, dest, (newRoomCode) {
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
      case MeetState.editingRoom:
        return CreateOrEditRoomView(
          isEditing: true,
          roomCode: _editingRoomCode,
          initialName: _editingRoomName,
          initialDestination: _editingDestination,
          meetRepo: widget.meetRepo,
          onSave: (newName, newDest) async {
            await widget.meetRepo.updateRoomDetails(_editingRoomCode, newName, newDest);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("모임 정보 및 목적지가 수정되었습니다."))
              );
              setState(() {
                _destination = newDest;
                _meetState = MeetState.lobby;
              });
            }
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
          onEditRoom: (code, name, dest) {
            _startEditingRoomFromCode(code, name, dest);
          },
        );
    }
  }
}

class LobbyView extends StatefulWidget {
  final MeetRepository meetRepo;
  final Function(String) onCreateRoom;
  final Function(String) onJoinRoom;
  final Function(RoomInfo) onEditRoom;

  const LobbyView({
    Key? key,
    required this.meetRepo,
    required this.onCreateRoom,
    required this.onJoinRoom,
    required this.onEditRoom,
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
                  Expanded(
                    child: InkWell(
                      onTap: () => _showHistoryMapPopup(room),
                      child: Text(
                        shortName,
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (room.isHost) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color(0xFF00E5FF), size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: "방 관리/수정",
                      onPressed: () {
                        widget.onEditRoom(room);
                      },
                    ),
                  ],
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
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                    tooltip: "방 삭제",
                    onPressed: () => _confirmDeleteRoomInLobby(room),
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
                    icon: const Icon(Icons.exit_to_app, color: Colors.orangeAccent, size: 18),
                    tooltip: "방 나가기",
                    onPressed: () => _confirmLeaveRoomInLobby(room),
                  )
                ],
              )
          ],
        ),
      ),
    );
  }

  void _showHistoryMapPopup(RoomInfo room) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
      ),
    );

    try {
      final dest = LatLng(room.destLat, room.destLon);
      final members = await widget.meetRepo.getRoomMembersOnce(room.roomCode);

      if (context.mounted) Navigator.pop(context);

      if (dest.latitude == 0.0 && dest.longitude == 0.0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("모임 목적지 정보가 올바르지 않습니다.", style: TextStyle(color: Colors.white)),
              backgroundColor: Color(0xFF1E293B),
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) {
            final markers = <Marker>[
              Marker(
                point: dest!,
                width: 75,
                height: 55,
                child: buildSleekFlagMarker(label: "목적지"),
              ),
            ];

            final polylines = <Polyline>[];

            for (var m in members) {
              if (m.location.latitude != 0.0 && m.location.longitude != 0.0) {
                final displayStr = m.name;
                final calcWidth = (displayStr.length * 11.0 + 24.0).clamp(70.0, 240.0);
                markers.add(
                  Marker(
                    point: m.location,
                    width: calcWidth,
                    height: 55,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Color(m.color), width: 1.5),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                          ),
                          child: Text(
                            displayStr,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Icon(Icons.person_pin_circle, color: Color(m.color), size: 28),
                      ],
                    ),
                  ),
                );
              }

              final filteredPath = filterGlitchLatLngPoints(m.path);
              List<LatLng> drawPoints = [];
              if (filteredPath.length >= 2) {
                drawPoints = filteredPath;
              } else if (filteredPath.length == 1 && (m.location.latitude != 0.0 || m.location.longitude != 0.0)) {
                final dist = Geolocator.distanceBetween(
                  filteredPath.first.latitude, filteredPath.first.longitude,
                  m.location.latitude, m.location.longitude
                );
                if (dist > 0.5) {
                  drawPoints = [filteredPath.first, m.location];
                } else if (dest.latitude != 0.0 && dest.longitude != 0.0) {
                  drawPoints = [filteredPath.first, dest];
                }
              } else if (m.location.latitude != 0.0 || m.location.longitude != 0.0) {
                if (dest.latitude != 0.0 && dest.longitude != 0.0) {
                  drawPoints = [m.location, dest];
                }
              }

              if (drawPoints.length >= 2) {
                polylines.add(
                  Polyline(
                    points: drawPoints,
                    strokeWidth: 9.0,
                    color: const Color(0xFF0F172A),
                  ),
                );
                polylines.add(
                  Polyline(
                    points: drawPoints,
                    strokeWidth: 5.0,
                    color: Color(m.color),
                  ),
                );
              }
            }

            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "${room.name} 이동 경로",
                            style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: dest!,
                            initialZoom: 13.0,
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
                    const SizedBox(height: 12),
                    const Text(
                      "참여자 목록",
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: members.isEmpty
                          ? const Center(child: Text("참여자가 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 12)))
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: members.length,
                              itemBuilder: (c, idx) {
                                final m = members[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 12.0),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Color(m.color),
                                        radius: 10,
                                        child: Text(
                                          m.name.isNotEmpty ? m.name[0] : "?",
                                          style: const TextStyle(color: Colors.white, fontSize: 8),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        m.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("이력 지도를 불러오지 못했습니다: $e")),
        );
      }
    }
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

  void _confirmDeleteRoomInLobby(RoomInfo room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text("${room.name} 삭제", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("정말 이 모임 방을 삭제하시겠습니까?\n모든 데이터가 삭제되며 복구할 수 없습니다.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.meetRepo.deleteRoom(room.roomCode);
              if (mounted) {
                setState(() {
                  _myMeets.removeWhere((r) => r.roomCode == room.roomCode);
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모임 방이 삭제되었습니다.")));
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveRoomInLobby(RoomInfo room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text("${room.name} 나가기", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("이 모임 방에서 나가시겠습니까?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.meetRepo.deleteRoom(room.roomCode);
              if (mounted) {
                setState(() {
                  _myMeets.removeWhere((r) => r.roomCode == room.roomCode);
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모임 방에서 나왔습니다.")));
              }
            },
            child: const Text("나가기", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class DestinationSearchWidget extends StatefulWidget {
  final Function(LatLng pos, String placeName) onDestinationSelected;

  const DestinationSearchWidget({Key? key, required this.onDestinationSelected}) : super(key: key);

  @override
  State<DestinationSearchWidget> createState() => _DestinationSearchWidgetState();
}

class _DestinationSearchWidgetState extends State<DestinationSearchWidget> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final uri = Uri.parse("https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&accept-language=ko&limit=5");
      final response = await http.get(uri, headers: {'User-Agent': 'SmartHealthFlutter/1.0'});
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          _searchResults = data.map((item) => {
            'display_name': item['display_name'] ?? '',
            'lat': double.parse(item['lat']),
            'lon': double.parse(item['lon']),
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "목적지 장소/주소 검색 (예: 서울역, 강남역)",
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0x33FFFFFF),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                onSubmitted: _performSearch,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: _isSearching
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                  : const Icon(Icons.search, color: Color(0xFF00E5FF)),
              onPressed: () => _performSearch(_searchCtrl.text),
            ),
          ],
        ),
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
              itemBuilder: (context, idx) {
                final item = _searchResults[idx];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                  title: Text(item['display_name'], style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    final pos = LatLng(item['lat'], item['lon']);
                    widget.onDestinationSelected(pos, item['display_name']);
                    setState(() => _searchResults = []);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class CreateOrEditRoomView extends StatefulWidget {
  final bool isEditing;
  final String roomCode;
  final String initialName;
  final LatLng? initialDestination;
  final MeetRepository meetRepo;
  final Function(String name, LatLng dest) onSave;
  final VoidCallback onCancel;

  const CreateOrEditRoomView({
    Key? key,
    this.isEditing = false,
    this.roomCode = "",
    this.initialName = "",
    this.initialDestination,
    required this.meetRepo,
    required this.onSave,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<CreateOrEditRoomView> createState() => _CreateOrEditRoomViewState();
}

class _CreateOrEditRoomViewState extends State<CreateOrEditRoomView> {
  late TextEditingController _nameController;
  LatLng? _tempDest;
  String? _selectedPlaceName;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _tempDest = widget.initialDestination;
    if (widget.initialDestination != null) {
      _selectedPlaceName = "지정된 목적지 (${widget.initialDestination!.latitude.toStringAsFixed(4)}, ${widget.initialDestination!.longitude.toStringAsFixed(4)})";
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showInviteDialog() {
    widget.meetRepo.fetchUsers((usersList) {
      showDialog(context: context, builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("참여자 추가 (초대)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: usersList.isEmpty
                ? const Text("초대할 수 있는 가입자 목록이 없습니다.", style: TextStyle(color: Colors.white70))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: usersList.length,
                    itemBuilder: (context, index) {
                      final user = usersList[index];
                      return ListTile(
                        leading: const Icon(Icons.person_add, color: Color(0xFF00E5FF)),
                        title: Text(user['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기", style: TextStyle(color: Colors.grey))),
          ],
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleStr = widget.isEditing ? "✏️ 모임 방 관리 및 수정" : "➕ 새로운 모임 방 만들기";
    final subStr = widget.isEditing 
        ? "종료 전까지 목적지, 모임명, 참여자 초대를 자유롭게 변경할 수 있습니다." 
        : "목적지와 모임명을 정하고 초대 코드를 발급받으세요.";
    final btnStr = widget.isEditing ? "수정 완료 (저장)" : "방 생성 및 초대코드 발급";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleStr, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subStr, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
            if (widget.isEditing)
              ElevatedButton.icon(
                icon: const Icon(Icons.person_add, size: 16, color: Colors.white),
                label: const Text("참여자 초대", style: TextStyle(fontSize: 12, color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
                onPressed: _showInviteDialog,
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: "모임명",
            labelStyle: const TextStyle(color: Color(0xFF00E5FF)),
            hintText: "모임 이름을 입력하세요",
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0x33FFFFFF),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        DestinationSearchWidget(
          onDestinationSelected: (pos, placeName) {
            setState(() {
              _tempDest = pos;
              _selectedPlaceName = placeName;
            });
            _mapController.move(pos, 15.0);
          },
        ),
        if (_selectedPlaceName != null) ...[
          const SizedBox(height: 4),
          Text("선택한 장소: $_selectedPlaceName", style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _tempDest ?? const LatLng(37.5665, 126.9780),
                initialZoom: 15.0,
                onTap: (tapPosition, point) {
                  setState(() {
                    _tempDest = point;
                    _selectedPlaceName = "지정한 위치 (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})";
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
                        width: 75,
                        height: 55,
                        child: buildSleekFlagMarker(label: "목적지"),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: widget.onCancel,
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white)),
              child: const Text("취소", style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: _tempDest != null ? () {
                final name = _nameController.text.trim().isEmpty ? "모임" : _nameController.text.trim();
                widget.onSave(name, _tempDest!);
              } : null,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
              child: Text(btnStr, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ],
    );
  }
}

class InRoomLiveMap extends StatefulWidget {
  final String roomCode;
  final LatLng initialDestination;
  final MeetRepository meetRepo;
  final VoidCallback onLeave;
  final Function(String roomCode, String roomName, LatLng dest)? onEditRoom;

  const InRoomLiveMap({
    Key? key,
    required this.roomCode,
    required this.initialDestination,
    required this.meetRepo,
    required this.onLeave,
    this.onEditRoom,
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
  final MapController _mapController = MapController();

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

    LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "🤝 Meet 실시간 위치 공유 중",
          notificationText: "모임 멤버들과 실시간 위치 및 이동 동선을 공유하고 있습니다.",
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );
    }

    _locSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
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
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("참여자 추가 (초대)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: usersList.isEmpty
                ? const Text("초대할 수 있는 가입자 목록이 없습니다.", style: TextStyle(color: Colors.white70))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: usersList.length,
                    itemBuilder: (context, index) {
                      final user = usersList[index];
                      return ListTile(
                        leading: const Icon(Icons.person_add, color: Color(0xFF00E5FF)),
                        title: Text(user['name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("닫기", style: TextStyle(color: Colors.grey))),
          ],
        );
      });
    });
  }

  void _confirmDeleteRoom() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("방 삭제", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("정말 이 모임 방을 삭제하시겠습니까?\n모든 참여자에게 모임 방이 종료됩니다.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.meetRepo.deleteRoom(widget.roomCode);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모임 방이 삭제되었습니다.")));
                widget.onLeave();
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveRoom() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("방 나가기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("모임 방에서 나가시겠습니까?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.meetRepo.deleteRoom(widget.roomCode);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모임 방에서 나왔습니다.")));
                widget.onLeave();
              }
            },
            child: const Text("나가기", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Marker> markers = [];
    List<Polyline> polylines = [];

    markers.add(Marker(
      point: _tempDestination ?? _destination,
      width: 75,
      height: 55,
      child: buildSleekFlagMarker(label: "목적지"),
    ));

    for (var member in _members) {
      if (!member.isParticipating) continue;

      final filteredMemberPath = filterGlitchLatLngPoints(member.path);
      if (filteredMemberPath.length >= 2) {
        // 1. Dark Outline Polyline (배경 지도와 선명하게 분리해 주는 검은색 외곽선)
        polylines.add(Polyline(
          points: filteredMemberPath,
          color: const Color(0xFF0F172A),
          strokeWidth: 9.0,
        ));
        // 2. Bright Vibrant Member Color Polyline (참여자 고유 색상 메인 선)
        polylines.add(Polyline(
          points: filteredMemberPath,
          color: Color(member.color).withOpacity(1.0),
          strokeWidth: 5.0,
        ));
      } else if (filteredMemberPath.length == 1 && (member.location.latitude != 0.0 || member.location.longitude != 0.0)) {
        final dist = Geolocator.distanceBetween(
          filteredMemberPath.first.latitude, filteredMemberPath.first.longitude,
          member.location.latitude, member.location.longitude
        );
        if (dist > 0.5) {
          final pts = [filteredMemberPath.first, member.location];
          polylines.add(Polyline(
            points: pts,
            color: const Color(0xFF0F172A),
            strokeWidth: 9.0,
          ));
          polylines.add(Polyline(
            points: pts,
            color: Color(member.color).withOpacity(1.0),
            strokeWidth: 5.0,
          ));
        }
      }

      if (member.location.latitude != 0.0 || member.location.longitude != 0.0) {
        bool isMe = member.id == widget.meetRepo.getCurrentUserId();
        String displayStr = isMe ? "${member.name} (나)" : member.name;
        final calcWidth = (displayStr.length * 11.0 + 24.0).clamp(70.0, 240.0);
        
        markers.add(Marker(
          point: member.location,
          width: calcWidth,
          height: 55,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Color(member.color), width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                ),
                child: Text(
                  displayStr,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Icon(Icons.person_pin_circle, color: Color(member.color), size: 28),
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
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
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
                                Expanded(
                                  child: Text(widget.roomCode, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.copy, color: Colors.white, size: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.white),
                          style: IconButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
                          tooltip: "완료 (목록으로 이동)",
                          onPressed: widget.onLeave,
                        ),
                        const SizedBox(width: 6),
                        if (_isHost) ...[
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.black),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFF00E5FF)),
                            tooltip: "방 관리/수정",
                            onPressed: () {
                              widget.onEditRoom?.call(widget.roomCode, widget.roomCode, _destination);
                            },
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.person_add, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFF4285F4)),
                            tooltip: "참여자 추가",
                            onPressed: _showInviteDialog,
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
                            tooltip: "방 삭제",
                            onPressed: _confirmDeleteRoom,
                          ),
                        ] else ...[
                          IconButton(
                            icon: const Icon(Icons.exit_to_app, color: Colors.white),
                            style: IconButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
                            tooltip: "방 나가기",
                            onPressed: _confirmLeaveRoom,
                          ),
                        ],
                      ],
                    )
                  ],
                ),
                if (_isHost && _isEditingDestination) ...[
                  const SizedBox(height: 8),
                  DestinationSearchWidget(
                    onDestinationSelected: (pos, placeName) {
                      setState(() {
                        _tempDestination = pos;
                      });
                      _mapController.move(pos, 15.0);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              mapController: _mapController,
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
        const SizedBox(height: 12),
        Card(
          color: const Color(0x22FFFFFF),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("참여자 목록 (${_members.length}명)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 75,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final m = _members[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 18.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(m.color),
                              radius: 18,
                              child: Text(m.name.isNotEmpty ? m.name[0] : "?", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.name,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: m.isParticipating ? Colors.white : Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                decoration: m.isParticipating ? null : TextDecoration.lineThrough
                              ),
                            ),
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

List<LatLng> filterGlitchLatLngPoints(List<LatLng> raw) {
  final valid = raw.where((p) => p.latitude != 0.0 && p.longitude != 0.0).toList();
  if (valid.length < 2) return valid;

  List<LatLng> filtered = [];
  for (int i = 0; i < valid.length; i++) {
    final curr = valid[i];
    if (filtered.isEmpty) {
      filtered.add(curr);
      continue;
    }
    final prev = filtered.last;
    final dist = Geolocator.distanceBetween(
      prev.latitude, prev.longitude,
      curr.latitude, curr.longitude,
    );

    if (dist <= 500.0) {
      filtered.add(curr);
    } else if (i + 1 < valid.length) {
      // If dist > 500m, check if next point is close to curr (meaning user moved to a new cluster)
      final next = valid[i + 1];
      final distToNext = Geolocator.distanceBetween(
        curr.latitude, curr.longitude,
        next.latitude, next.longitude,
      );
      if (distToNext <= 500.0) {
        filtered.add(curr);
      }
    } else {
      filtered.add(curr);
    }
  }
  return filtered;
}
