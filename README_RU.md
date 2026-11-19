# LEVELUP TEST — Flutter + Google ML Kit + Android 16

Этот архив — **не готовый APK**, а полные авторские исходники **технической проверки**. Он рассчитан на `flutter create` (создание стандартных файлов Android/Gradle у пользователя) и Pixel 7 Pro с Android 16.

Сценарий: **открываешь YouTube → появляется добровольный экран LevelUp → нажимаешь «Start challenge» → 5 приседаний перед камерой → 5 минут доступа к YouTube**.

### Зачем Flutter + Kotlin?
Flutter — экран, камера, ML Kit; Kotlin — Android Accessibility Service для отслеживания активного пакета приложения и показа проверочного ограничительного слоя. Это исследовательский добровольный gate, **не абсолютная системная блокировка**. Только YouTube/Instagram/TikTok. Сервис **не извлекает и не читает содержимое экранов**, не использует root и не блокирует настройки, звонки или кнопку Home.

## 1. Подготовь инструменты

1. Установи **Git**, **VS Code** с расширениями Flutter/Dart, **Flutter SDK**, **Android Studio** (нужно для Android SDK, даже если код пишешь только в VS Code). Android Studio → SDK Manager → установи Android SDK Platform 36, Platform-Tools, Build-Tools, Command-line Tools, необходимую JDK 17 (обычно встроена в Android Studio).
2. В терминале VS Code:
   ```powershell
   flutter --version
   flutter doctor -v
   flutter doctor --android-licenses
   ```
   Прими лицензии. Если `flutter` не найден — установи SDK через VS Code `Ctrl+Shift+P` → `Flutter: New Project` → `Download SDK`, либо вручную и добавь папку `flutter/bin` в PATH. Если Android SDK не найден, открой SDK Manager или задай `flutter config --android-sdk "C:\Users\YOURNAME\AppData\Local\Android\Sdk"` (замени путь на свой).
3. **Для этого проекта нужен свежий Flutter/Dart**: SDK Dart не ниже 3.11, поскольку использованы новые версии пакетов. Если Flutter старый, запусти `flutter upgrade`.

## 2. Создай стандартный проект Flutter

**PowerShell в VS Code на Windows:**
```powershell
cd D:\Projects
flutter create --org com.levelup --platforms=android levelup_test
cd levelup_test
code .
```
Если `D:\Projects` не существует, сначала создай: `New-Item -ItemType Directory -Force D:\Projects`.

ВАЖНО: название папки и организация должны быть как в команде. Мы используем нативный Kotlin package `com.levelup.levelup_test`. Другой package name потребует исправления Kotlin и Manifest.

## 3. Перенеси файлы архива

Открой ZIP `LevelUp_Test_Kit.zip` и **скопируй его содержимое поверх** созданной папки `levelup_test`, сохраняя структуру путей. Соглашайся заменить `pubspec.yaml`, `lib/main.dart`, `android/app/src/main/AndroidManifest.xml`.

Должны существовать:
- `levelup_test/pubspec.yaml`
- `levelup_test/lib/main.dart`
- `levelup_test/android/app/src/main/AndroidManifest.xml`
- `levelup_test/android/app/src/main/kotlin/com/levelup/levelup_test/MainActivity.kt`
- `levelup_test/android/app/src/main/kotlin/com/levelup/levelup_test/LevelUpAccessibilityService.kt`
- `levelup_test/android/app/src/main/res/xml/levelup_accessibility_service.xml`
- `levelup_test/android/app/src/main/res/values/strings.xml`
- `levelup_test/setup_windows.ps1`

## 4. Настрой Android 16

В терминале корня проекта:
```powershell
powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
```
Он заменяет `compileSdk`, `targetSdk` на 36 и `minSdk` на 24 в сгенерированном `android/app/build.gradle.kts`, затем выполняет `flutter pub get`.

Если скрипт не работает, открой `android/app/build.gradle.kts` и **внутри** `android { ... }` поставь:
```kotlin
compileSdk = 36
// inside defaultConfig:
minSdk = 24
targetSdk = 36
```
Остальное в Gradle оставь как было. Запусти `flutter pub get`.

### Модель Google
**Отдельно скачивать `.tflite` НЕ НУЖНО.** Пакет `google_mlkit_pose_detection` подключает нативный Google ML Kit Pose Detection SDK. Gradle скачает необходимые зависимости при первой сборке (нужен интернет). В коде создаётся `PoseDetector(model: PoseDetectionModel.base, mode: PoseDetectionMode.stream)`. Для прямого ручного MediaPipe нужен другой набор файлов, но здесь он не используется.

## 5. Подключи Pixel 7 Pro USB-кабелем

1. Pixel → **Настройки → О телефоне → Номер сборки**. Нажми 7 раз.
2. **Настройки → Система → Для разработчиков → Отладка по USB** → включить.
3. Подключи **кабелем, который передаёт данные**, не только заряжает.
4. На телефоне появится «Разрешить отладку по USB с этого компьютера?» → разреши.
5. В терминале:
   ```powershell
   flutter devices
   adb devices
   ```
   Pixel должен быть в списке. Если `adb` не найден, используй `flutter devices` или запусти adb из папки Android SDK `platform-tools`. На Windows при отсутствии устройства установи **Google USB Driver** через Android Studio → SDK Manager → SDK Tools; проверь кабель/USB-режим и подтверждение RSA.

## 6. Запусти тестовое приложение

В корне Flutter-проекта:
```powershell
flutter run
```
При первом запуске Android SDK/Gradle и зависимости скачиваются. **Debug APK устанавливается на подключённый телефон автоматически.** В VS Code можно также выбрать Pixel внизу и нажать `F5`.

Чтобы просто собрать APK:
```powershell
flutter build apk --debug
```
Ищи его по пути `build/app/outputs/flutter-apk/app-debug.apk`.

## 7. Включи тестовое разрешение Android

1. Открой **LevelUp Test** на Pixel.
2. Выбери `YouTube` (советую сначала его, потому что он обычно установлен).
3. Нажми `Открыть спец. возможности` (Accessibility Settings).
4. Найди **LevelUp Test — voluntary app gate** в установленных/загруженных сервисах и **включи вручную**.
5. На Android 16 для некоторых приложений, установленных не из магазина, сервис может быть заблокирован «Restricted setting». Если Android показывает запрет, **только если доверяешь собственному исходному коду**, открой **Настройки → Приложения → LevelUp Test → ⋮ → Allow restricted settings**, подтвердить и повтори. У разных сборок Pixel меню отличается. Не нужно использовать сторонние приложения или ADB-обход защиты.
6. Вернись в LevelUp. Обнови статус кнопкой ↻. Включи тумблер `Режим включён`.

**Почему спрашивает Accessibility:** сервис получает только идентификатор активного приложения и показывает overlay при открытии выбранного приложения. Он не читает уведомления, сообщения и содержимое экранов. Разрешение всегда можно отозвать в настройках.

## 8. Проверь результат

1. В LevelUp выбери YouTube. `Accessibility Service включён`; тумблер ON; нажми «Сбросить доступ для теста».
2. Сверни LevelUp, вручную открой YouTube.
3. Ожидаем **полноэкранный слой LevelUp** с `Start challenge`, `Turn off gate`, `Return to home screen`.
4. `Start challenge` → экран камеры LevelUp.
5. Поставь Pixel на устойчивую подставку на расстоянии примерно 2–3 метра; пусть камера видит бедро, колено, голеностоп. Повернись чуть боком, освещение яркое.
6. Сделай пять **комфортных** приседаний из положения стоя и обратно. Счётчик: `0/5` → `5/5`.
7. Приложение должно предоставить 5 минут доступа и **попытаться открыть YouTube**.
8. Для быстрой повторной проверки вернись в LevelUp → `Сбросить доступ` → открой YouTube.
9. Проверь кнопку **выключить gate**. Пользователь всегда должен сохранять доступ к телефону.

### Не тестируй бесконечно
Если движение не считывается или вызывает дискомфорт, прекрати тест; пользователь всегда может выйти. Модель не оценивает медицинскую безопасность и не гарантирует качество техники.

## 9. Возможные ошибки

- **`flutter: command not found`** → Flutter SDK не установлен или `flutter/bin` не в PATH; перезапусти VS Code.
- **`No devices found`** → USB debug, кабель с передачей данных, подтвердить RSA, Windows-драйвер Google.
- **`SDK location not found`** → установи Android Studio SDK, посмотри SDK path в SDK Manager, затем `flutter config --android-sdk ...`.
- **`Platform 36 not installed`** → Android Studio → SDK Manager → Android 16 (API 36).
- **`minSdkVersion ... cannot be smaller than ...`** → проверь `minSdk = 24` в `android/app/build.gradle.kts`.
- **`Access to accessibility service is restricted`** → см. пункт 7, НЕ пытайся обходить защиту скрытыми методами.
- **YouTube открывается, барьер не появляется** → сервис не активен/тумблер OFF/5 минут ещё не истекли; обнови состояние. События могут приходить с задержкой, тестовая реализация не гарантирует блокировку на любом устройстве.
- **Слой исчезает при шторке/системных окнах** → это специально: системные интерфейсы не блокируются.
- **Камера просит разрешение** → выбери «Разрешить во время использования».
- **`Камера не передаёт NV21`** → обязательно оставь `camera_android` в pubspec, проверь что Flutter использует Camera2 backend.
- **Приседания не засчитываются** → отойди от камеры, встань боком, убедись, что видны колени и лодыжки; подсчёт основан на углах колен, тестовая точность не гарантирована.
- **Gradle / Kotlin version конфликт** → не заменяй Flutter-генерированный `android/build.gradle.kts` случайным кодом из интернета; обнови Flutter stable и переустанови SDK tools.
- **Если приложение работает только первый раз** → проверь в настройках Pixel оптимизацию батареи и что Android не остановил сервис. Для публичного продукта потребуются отдельные тесты и переработка background-части.

## 10. Чего тест НЕ делает

- Не блокирует все приложения и не обеспечивает неизбежную блокировку.
- Не запускается автоматически без добровольно выданного доступа.
- Не защищён от удаления и обхода.
- Не работает на iOS, в браузере или с эмулятором камеры без адаптации.
- Не гарантирует публикацию через Google Play. Accessibility API имеет ограничения и правила платформы.
- Не оценивает состояние здоровья или правильность спортивной техники.
- Не реализует регистрацию, XP, оплату, авторизацию и облачный backend.

## 11. Что записать после тестирования

| Проверка | Результат |
|---|---|
| Flutter запустился на Pixel Android 16 | да/нет |
| Android Accessibility разрешено | да/нет |
| Барьер появился поверх YouTube | да/нет |
| Кнопка Start challenge открыла Flutter | да/нет |
| Камера видит человека | да/нет |
| 5 настоящих приседаний засчитались | да/нет |
| YouTube открылся на 5 минут | да/нет |
| Через 5 минут барьер вернулся | да/нет |
| Кнопка отключения сработала | да/нет |

Рекомендуемый порядок: сначала **Flutter и камера**, затем **Accessibility**, затем **соединить всё**. Приложение нужно проверить на устройстве: исходники созданы, но в текущей среде без Flutter SDK и подключённого Pixel не были собраны в APK и испытаны.

Официальные справки:
- Flutter install: https://docs.flutter.dev/install
- Android setup: https://docs.flutter.dev/platform-integration/android/setup
- Google ML Kit Pose (Flutter): https://pub.dev/packages/google_mlkit_pose_detection
- Android restricted settings: https://support.google.com/android/answer/12623953
- AccessibilityService: https://developer.android.com/reference/android/accessibilityservice/AccessibilityService
