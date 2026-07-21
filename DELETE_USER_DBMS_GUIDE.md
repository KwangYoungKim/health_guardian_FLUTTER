# 🗑️ Health Guardian 백엔드 DBMS 사용자(DragonKim) 삭제 조치 가이드

본 문서는 **Smart Health Guardian** 백엔드 서버(116.123.208.138:8099) 및 데이터베이스(DBMS)에서 특수 사용자(**`DragonKim`** 또는 지정 닉네임) 및 연관된 모든 데이터(알람, 걷기 동선, 걸음 수, 약 복용, 메모, 병원 방문 등)를 완벽하게 삭제하기 위한 조치 가이드입니다.

---

## 📌 1. PostgreSQL DBMS 직접 삭제 SQL 스크립트

원격 DB(PostgreSQL)에 접속(pgAdmin, psql CLI 등)하여 아래 SQL 트랜잭션을 실행하면 해당 사용자 및 연관 데이터가 일괄 처리됩니다.

```sql
-- ============================================================
-- 1. 사용자 ID 조회 및 확인 (닉네임: DragonKim)
-- ============================================================
SELECT id, nickname, pin FROM app_users WHERE nickname = 'DragonKim';

-- ============================================================
-- 2. DragonKim 연관 테이블 통합 연쇄 삭제 (단일 트랜잭션)
-- ============================================================
BEGIN;

-- ① 알람 데이터 삭제
DELETE FROM alarm 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

-- ② 걷기 GPS 이동 경로 데이터 삭제
DELETE FROM daily_path 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

-- ③ 걸음 수 기록 데이터 삭제
DELETE FROM step_data 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

-- ④ 풍부한 위치 메모 데이터 삭제
DELETE FROM rich_memo 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

-- ⑤ 약 복용 항목 및 복용 기록 삭제
DELETE FROM medication_log 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

DELETE FROM medication_item 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

-- ⑥ 병원 방문 일정 데이터 삭제
DELETE FROM hospital_visit 
WHERE user_id IN (SELECT id FROM app_users WHERE nickname = 'DragonKim');

-- ⑦ 최종 사용자(app_users) 계정 삭제
DELETE FROM app_users 
WHERE nickname = 'DragonKim';

COMMIT;
```

---

## 🛠️ 2. Spring Boot 백엔드 서버 REST API 구현 (`UserController.kt`)

플러터 앱의 설정 화면에서 계정 삭제 버튼을 눌렀을 때 백엔드 서버에서 자동으로 처리할 수 있도록 Spring Boot 컨트롤러에 삭제 엔드포인트를 탑재합니다.

### 📌 `UserController.kt` 또는 `SyncController.kt`

```kotlin
import org.springframework.web.bind.annotation.*
import org.springframework.http.ResponseEntity
import org.springframework.transaction.annotation.Transactional

@RestController
@RequestMapping("/api/users")
class UserController(
    private val userRepository: UserRepository,
    private val alarmRepository: AlarmRepository,
    private val dailyPathRepository: DailyPathRepository,
    private val stepDataRepository: StepDataRepository,
    private val richMemoRepository: RichMemoRepository,
    private val medicationItemRepository: MedicationItemRepository,
    private val medicationLogRepository: MedicationLogRepository,
    private val hospitalVisitRepository: HospitalVisitRepository
) {

    /**
     * 사용자 ID 기반 영구 삭제 (REST DELETE /api/users/{userId})
     */
    @Transactional
    @DeleteMapping("/{userId}")
    fun deleteUser(@PathVariable userId: String): ResponseEntity<Map<String, Any>> {
        val userOpt = userRepository.findById(userId)
        if (userOpt.isEmpty) {
            return ResponseEntity.notFound().build()
        }

        // 연관 데이터 연쇄 삭제
        alarmRepository.deleteByUserId(userId)
        dailyPathRepository.deleteByUserId(userId)
        stepDataRepository.deleteByUserId(userId)
        richMemoRepository.deleteByUserId(userId)
        medicationItemRepository.deleteByUserId(userId)
        medicationLogRepository.deleteByUserId(userId)
        hospitalVisitRepository.deleteByUserId(userId)

        // 사용자 본인 삭제
        userRepository.deleteById(userId)

        return ResponseEntity.ok(mapOf(
            "success" to true,
            "message" to "User $userId and all associated data deleted successfully."
        ))
    }

    /**
     * 닉네임 기반 영구 삭제 (REST DELETE /api/users/nickname/{nickname})
     */
    @Transactional
    @DeleteMapping("/nickname/{nickname}")
    fun deleteUserByNickname(@PathVariable nickname: String): ResponseEntity<Map<String, Any>> {
        val user = userRepository.findByNickname(nickname)
            ?: return ResponseEntity.notFound().build()

        return deleteUser(user.id)
    }
}
```

---

## 🔥 3. Firebase Realtime Database 노드 삭제

실시간 모임 및 위치 추적 노드가 Firebase Realtime Database에 저장되어 있는 경우 아래 절차로 삭제합니다.

### 방법 1) Firebase Web Console
1. [Firebase 콘솔](https://console.firebase.google.com/) 접속 ➔ 프로젝트 선택.
2. **Build** ➔ **Realtime Database** 메뉴 이동.
3. `users` 노드 하위에서 `DragonKim`에 해당하는 `user_id` 노드 (예: `users/{userId}`) 마우스 호버 ➔ **X (삭제)** 클릭.

### 방법 2) cURL REST API 삭제
```bash
# 사용자 UUID 기반 노드 삭제
curl -X DELETE "https://<YOUR-FIREBASE-PROJECT-ID>.firebaseio.com/users/<USER_UUID>.json"
```

---

## ✅ 4. 삭제 검증 및 리셋 확인 절차

1. **앱 로그인 테스트**: 플러터 앱에서 `DragonKim` 닉네임과 PIN으로 로그인을 시도했을 때 `계정을 찾을 수 없습니다` 또는 회원가입 안내 메시지가 정상 출력되는지 확인.
2. **설정 화면 노출 검증**:
   - `DragonKim` 로그인 시: 설정 화면 상단에 🚨 **"DragonKim 계정 및 서버 데이터 삭제"** 빨간색 전용 버튼 노출.
   - 타 닉네임 로그인 시: 해당 전용 삭제 버튼이 완전히 숨겨짐(미노출).
