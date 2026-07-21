# 🛡️ 백엔드 서버 원스톱 사용자 삭제 API 연동 가이드

본 문서는 플러터 앱의 슈퍼 계정(**`DragonKim`**)이 **"원스톱 통합 삭제"** 버튼을 눌렀을 때 백엔드 원격 서버(116.123.208.138:8099)의 PostgreSQL DBMS에서도 해당 사용자의 모든 관련 데이터가 자동으로 삭제되도록 Spring Boot 서버 코드를 추가하는 가이드입니다.

---

## 📌 1. Spring Boot 레포지토리(Repository) 삭제 메서드 추가

Spring Boot 프로젝트의 각 Repository 인터페이스에 `deleteByUserId(userId: String)` 메서드를 추가합니다.

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

## 🛠️ 2. `UserController.kt` 삭제 컨트롤러 엔드포인트 추가

Spring Boot 컨트롤러 클래스에 아래 코드를 추가하신 후 서버를 새로 재빌드(`./gradlew build`)하여 실행합니다.

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
     * 앱의 슈퍼 관리자(DragonKim) 원스톱 삭제 연동 REST API
     * HTTP DELETE http://116.123.208.138:8099/api/users/{userId}
     */
    @Transactional
    @DeleteMapping("/{userId}")
    fun deleteUser(@PathVariable userId: String): ResponseEntity<Map<String, Any>> {
        val userOpt = userRepository.findById(userId)
        if (userOpt.isEmpty) {
            return ResponseEntity.notFound().build()
        }

        // 1. 연관된 7개 데이터 테이블 연쇄 삭제
        alarmRepository.deleteByUserId(userId)
        dailyPathRepository.deleteByUserId(userId)
        stepDataRepository.deleteByUserId(userId)
        richMemoRepository.deleteByUserId(userId)
        medicationItemRepository.deleteByUserId(userId)
        medicationLogRepository.deleteByUserId(userId)
        hospitalVisitRepository.deleteByUserId(userId)

        // 2. 최종 app_users 테이블에서 사용자 삭제
        userRepository.deleteById(userId)

        return ResponseEntity.ok(mapOf(
            "success" to true,
            "message" to "User $userId and all associated records deleted successfully from PostgreSQL DBMS."
        ))
    }
}
```

---

## ✅ 3. 서버 적용 방법

1. 원격 백엔드 서버(116.123.208.138)의 Spring Boot 프로젝트 코드를 위 내용대로 수정합니다.
2. `./gradlew build` 명령어로 프로젝트를 빌드합니다.
3. `./gradlew bootRun` (또는 JAR 실행)으로 서버를 재시작합니다.
4. 이제 앱 설정의 **"🛡️ [슈퍼 계정 전용] 등록 사용자 관리 및 원스톱 통합 삭제"** 창에서 🗑️ **[원스톱 삭제]**를 누르면 **PostgreSQL DBMS와 Firebase DB가 동시에 자동 연동 삭제**됩니다!
