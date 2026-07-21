# 📋 [작업지시서] Health Guardian 백엔드 서버 사용자 원스톱 삭제 API 구현

**문서 번호**: WO-20260721-01  
**작성 일자**: 2026년 07월 21일  
**대상 시스템**: Health Guardian 원격 백엔드 서버 (`http://116.123.208.138:8099`)  
**작성 목적**: 앱 내 슈퍼 관리자(`DragonKim`)의 사용자 🗑️ **[원스톱 통합 삭제]** 기능 연동을 위해, 백엔드 PostgreSQL DBMS에서 해당 사용자 및 모든 연관 데이터를 연쇄 삭제(Cascade Delete)하는 REST API 구현 및 반영.

---

## 📌 1. REST API 사양 (Specification)

| 항목 | 상세 내용 |
|---|---|
| **HTTP Method** | `DELETE` |
| **요청 URL** | `http://116.123.208.138:8099/api/users/{userId}` |
| **Path Variable** | `{userId}` : 삭제 대상 사용자의 UUID (예: `ebd3a404-6780-43de-b058-60e33abdb9fa`) |
| **Request Header** | `Content-Type: application/json` |
| **Response Format** | `application/json` |

### Response 예시
- **성공 (200 OK)**:
  ```json
  {
    "success": true,
    "message": "User ebd3a404-6780-43de-b058-60e33abdb9fa and all associated records deleted successfully."
  }
  ```
- **대상을 찾지 못함 (404 Not Found)**:
  ```json
  {
    "success": false,
    "message": "User not found"
  }
  ```

---

## 🗄️ 2. PostgreSQL DBMS 삭제 대상 테이블 및 순서

단일 데이터베이스 트랜잭션(`@Transactional`) 내에서 외래 키 참조 관계를 고려하여 아래 8개 테이블 순서로 삭제를 진행합니다.

1. `alarm` 테이블: `WHERE user_id = {userId}`
2. `daily_path` 테이블: `WHERE user_id = {userId}`
3. `step_data` 테이블: `WHERE user_id = {userId}`
4. `rich_memo` 테이블: `WHERE user_id = {userId}`
5. `medication_log` 테이블: `WHERE user_id = {userId}`
6. `medication_item` 테이블: `WHERE user_id = {userId}`
7. `hospital_visit` 테이블: `WHERE user_id = {userId}`
8. `app_users` (또는 `users`) 테이블: `WHERE id = {userId}`

---

## 🛠️ 3. Spring Boot 백엔드 수정 소스 코드 (Kotlin 기준)

### 3-1. Repository 인터페이스 수정 (`deleteByUserId` 추가)

각 Repository 파일에 `deleteByUserId(userId: String)` 메서드를 추가합니다:

```kotlin
// AlarmRepository.kt
interface AlarmRepository : JpaRepository<Alarm, String> {
    fun deleteByUserId(userId: String)
}

// DailyPathRepository.kt
interface DailyPathRepository : JpaRepository<DailyPath, String> {
    fun deleteByUserId(userId: String)
}

// StepDataRepository.kt
interface StepDataRepository : JpaRepository<StepData, String> {
    fun deleteByUserId(userId: String)
}

// RichMemoRepository.kt
interface RichMemoRepository : JpaRepository<RichMemo, String> {
    fun deleteByUserId(userId: String)
}

// MedicationItemRepository.kt
interface MedicationItemRepository : JpaRepository<MedicationItem, String> {
    fun deleteByUserId(userId: String)
}

// MedicationLogRepository.kt
interface MedicationLogRepository : JpaRepository<MedicationLog, String> {
    fun deleteByUserId(userId: String)
}

// HospitalVisitRepository.kt
interface HospitalVisitRepository : JpaRepository<HospitalVisit, String> {
    fun deleteByUserId(userId: String)
}
```

---

### 3-2. `UserController.kt` 삭제 엔드포인트 추가

```kotlin
package com.example.health_guardian.controller

import org.springframework.web.bind.annotation.*
import org.springframework.http.ResponseEntity
import org.springframework.transaction.annotation.Transactional
import com.example.health_guardian.repository.*

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
     * 슈퍼 관리자 앱 연동 사용자 원스톱 영구 삭제 API
     */
    @Transactional
    @DeleteMapping("/{userId}")
    fun deleteUser(@PathVariable userId: String): ResponseEntity<Map<String, Any>> {
        val userOpt = userRepository.findById(userId)
        if (userOpt.isEmpty) {
            return ResponseEntity.status(404).body(mapOf("success" to false, "message" to "User not found"))
        }

        // 1. 연관 데이터 테이블 연쇄 삭제
        alarmRepository.deleteByUserId(userId)
        dailyPathRepository.deleteByUserId(userId)
        stepDataRepository.deleteByUserId(userId)
        richMemoRepository.deleteByUserId(userId)
        medicationItemRepository.deleteByUserId(userId)
        medicationLogRepository.deleteByUserId(userId)
        hospitalVisitRepository.deleteByUserId(userId)

        // 2. 최상위 사용자 계정 삭제
        userRepository.deleteById(userId)

        return ResponseEntity.ok(mapOf(
            "success" to true,
            "message" to "User $userId and all associated records deleted successfully."
        ))
    }
}
```

---

## 🚀 4. 배포 및 테스트 방법

1. 원격 서버(116.123.208.138)에 접속합니다.
2. 위 소스 코드를 추가한 후 Gradle 프로젝트를 빌드합니다:
   ```bash
   ./gradlew build
   ```
3. 서버 프로세스를 실행합니다:
   ```bash
   ./gradlew bootRun
   ```
4. cURL 명령어로 삭제 API 작동을 테스트합니다:
   ```bash
   curl -X DELETE http://116.123.208.138:8099/api/users/테스트_USER_ID
   ```

---

**작성자**: Antigravity AI Assistant  
**참조 파일**: [BACKEND_WORK_ORDER.md](file:///Users/kangsunkim/.gemini/antigravity/scratch/health_guardian_flutter/BACKEND_WORK_ORDER.md)
