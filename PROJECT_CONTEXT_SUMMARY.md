# 🛡️ Health Guardian 프로젝트 현황 & 새 대화 시작 가이드 (PROJECT_CONTEXT_SUMMARY.md)

> 💡 **새 채팅창 시작 시 사용법**:  
> 쿼터(토큰)를 대폭 아끼기 위해 새 대화창(New Chat)을 열었을 때, 아래 내용을 복사해서 첨부하거나 이 파일 경로를 AI에게 알려주시면 이전 작업 맥락을 100% 이해한 상태에서 쿼터를 80% 이상 절약하며 작업을 진행하실 수 있습니다.

---

## 📌 1. 프로젝트 기본 정보
* **앱 명칭**: Health Guardian (헬스 가디언 - 알람/약복용/병원/걷기/모임/메모 건강 관리 통합 앱)
* **맥북 소스 코드 경로**: `/Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter`
* **GitHub 저장소 주소**: [https://github.com/KwangYoungKim/health-guardian.git](https://github.com/KwangYoungKim/health-guardian.git)
  - `main` 브랜치: Android Kotlin 네이티브 + iOS Swift 네이티브 + Flutter UI 통합 소스
  - `backend` 브랜치: Spring Boot 서버 & APK 다운로드 컨트롤러 소스

---

## 🛠️ 2. 기술 스택 및 구조
* **프론트엔드 / 앱**: Flutter (Dart), Android Native (Kotlin), iOS Native (Swift)
* **백엔드 서버**: Spring Boot (Kotlin), REST API, Firebase Realtime Database
* **지도 및 위치**: OpenStreetMap (`flutter_map`), Geolocator
* **주요 서비스 파일**:
  - 알람 화면: [alarm_screen.dart](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/lib/screens/alarm_screen.dart)
  - 약 복용 화면: [medication_screen.dart](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/lib/screens/medication_screen.dart)
  - 병원 일정 화면: [hospital_screen.dart](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/lib/screens/hospital_screen.dart)
  - 걷기 & GPS 경로 화면: [walking_screen.dart](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/lib/screens/walking_screen.dart)
  - Meet 모임 화면: [meet_screen.dart](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/lib/screens/meet_screen.dart)
  - 메모 화면: [memo_screen.dart](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/lib/screens/memo_screen.dart)
  - 안드로이드 센서/알람 서비스: [AlarmSoundService.kt](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/android/app/src/main/kotlin/com/example/health_guardian_flutter/AlarmSoundService.kt)

---

## ✅ 3. 최근 완료된 핵심 패치 & 기능 목록
1. **우측 상단 빗금(레이아웃 오버플로우) 100% 해결**:
   - 닉네임(`👤 닉네임`)을 5개 주요 리스트 화면 제목 아래 세로(`Column`)로 줄바꿈 배치하여 우측 가로 폭 초과 에러(`RIGHT OVERFLOWED BY 41 PIXELS`)를 완전 제거함.
2. **알람 화면 실시간 카운트다운 (`상태: hh:mm:ss`) 표기**:
   - 알람 작동 중일 때 남은 시간을 1초 단위로 똑딱거리며 실시간 갱신되는 `00:12:45` 시/분/초 형식 적용. (정지 시 `상태: 정지됨`)
3. **알람 모드 명칭 전면 통일**:
   - 알람, 약 복용, 병원 화면의 알람 모드를 `벨+진동`, `진동`, `무음`, `벨` (선택된 시스템 벨소리)로 일관되게 표현함.
4. **GPS 순간 튐(Glitch) 보정 필터링 적용**:
   - 걷기 및 Meet 모임 지도에서 500m 이상 기하급수적으로 튀는 GPS 포인트 및 저정확도 위치를 자동으로 제외하는 `filterGlitchLatLngPoints` 보정 알고리즘 탑재.
5. **iOS & Android 크로스플랫폼 동시 반영**:
   - 모든 수정 사항이 안드로이드와 아이폰(iOS) 코드베이스에 동시 적용 및 GitHub 저장소 푸시 완료.
6. **안드로이드 최신 APK 웹 다운로드 서버 연동**:
   - Python HTTP 다운로드 서버(포트 9999)가 가동 중 (`http://192.168.1.25:9999/app-debug.apk` / `http://116.123.208.245:9999/app-debug.apk`).

---

## 🚀 4. 새로운 채팅창에서 AI에게 입력할 추천 프롬프트

> "안녕! 나는 Health Guardian 앱을 개발 중이야. 프로젝트 경로는 `/Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter` 이고, 최근 완성된 상태는 `PROJECT_CONTEXT_SUMMARY.md` 파일과 GitHub(`https://github.com/KwangYoungKim/health-guardian.git`)에 커밋되어 있어.  
> 오늘 추가로 작업하고 싶은 내용은 [원하는 작업 내용] 이야. 시작해 줘!"
