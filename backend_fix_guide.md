# 원격 백엔드 서버 조치 가이드 (116.123.208.138:8099)

현재 테스트 중인 플러터 앱이 실제 바라보고 있는 원격 백엔드 서버(116.123.208.138)에서 약 복용 데이터 동기화 시 **HTTP 500 (Internal Server Error)**가 발생하는 문제를 해결하기 위한 조치 사항입니다.

원격 서버에 접속하시어 Spring Boot 프로젝트 코드를 다음과 같이 수정하신 후 재빌드 및 서버 재시작을 진행해 주시면 됩니다.

---

## 1. `Entities.kt` 파일 수정
`MedicationItem` 클래스의 `times` 리스트를 가져올 때 발생하는 `LazyInitializationException`을 방지하기 위해 `FetchType.EAGER` 속성을 추가해야 합니다.

### 📌 수정 전
```kotlin
@Entity
data class MedicationItem(
    @Id
    val id: String,
    var userId: String? = null,
    val name: String,
    @ElementCollection
    val times: List<String>,
    val createdAt: String
)
```

### ✨ 수정 후
```kotlin
@Entity
data class MedicationItem(
    @Id
    val id: String,
    var userId: String? = null,
    val name: String,
    @ElementCollection(fetch = FetchType.EAGER) // <- 이 부분 추가
    val times: List<String>,
    val createdAt: String
)
```

---

## 2. `SyncController.kt` 파일 수정
데이터베이스 조회를 안전하게 트랜잭션 내에서 처리하도록 약 복용 데이터를 가져오는(`getMedications`) 함수에 `@Transactional` 어노테이션을 추가합니다.

### 📌 수정 사항 1: Import 추가
파일 최상단의 import 목록에 `Transactional` 패키지를 추가합니다.
```kotlin
import org.springframework.web.bind.annotation.*
import org.springframework.http.ResponseEntity
import org.springframework.transaction.annotation.Transactional // <- 이 줄 추가
```

### 📌 수정 사항 2: 함수에 어노테이션 적용
`getMedications` 함수 바로 위에 `@Transactional`을 붙여줍니다.
```kotlin
    @Transactional // <- 이 부분 추가
    @GetMapping("/sync/{userId}/medications")
    fun getMedications(@PathVariable userId: String): ResponseEntity<Map<String, Any>> {
        val items = medicationItemRepository.findByUserId(userId)
        val logs = medicationLogRepository.findByUserId(userId)
        return ResponseEntity.ok(mapOf("items" to items, "logs" to logs))
    }
```

---

## 3. 재빌드 및 재시작 (매우 중요)
코드를 모두 수정하신 후, 단순히 서버를 껐다 켜는 것만으로는 반영되지 않을 수 있습니다. 
반드시 **프로젝트를 새로 빌드(컴파일)** 하신 뒤 서버를 실행하셔야 합니다.

- **IntelliJ 등 IDE를 사용하시는 경우**: 상단의 `Build Project`(망치 모양 아이콘)를 클릭하여 빌드한 후 Run 버튼을 눌러주세요.
- **터미널을 사용하시는 경우**: 기존 서버 프로세스를 종료하고 `./gradlew build` 명령어로 새로 빌드하신 후 `./gradlew bootRun` (또는 JAR 파일 재실행)으로 켜주세요.

서버가 정상적으로 켜진 후, 폰의 플러터 앱에서 약 복용 일정을 새로 추가해 보시면 에러 없이 동기화가 완벽하게 작동할 것입니다!
