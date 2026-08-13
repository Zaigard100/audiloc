# Сборка под Android

В отличие от Windows, Android APK/AAB можно собрать прямо с Linux — но
в среде, где писался этот код, Android SDK не был установлен (это
отдельная по объёму, отдельно согласуемая установка — ~5–10 ГБ), так
что инструкция ниже не проверялась живой сборкой. См.
[`docs/roadmap.md`](roadmap.md).

## 1. Предварительные требования

1. **Java 17** (JDK). На Arch/CachyOS: `sudo pacman -S jdk17-openjdk`;
   на Debian/Ubuntu: `sudo apt install openjdk-17-jdk`. Проверить:
   `java -version`.

2. **Android SDK**. Проще всего через
   [Android Studio](https://developer.android.com/studio) (мастер
   первого запуска сам поставит SDK, platform-tools и NDK нужной
   версии) — либо только `cmdline-tools`, если Android Studio не
   нужна:
   ```bash
   mkdir -p ~/Android/Sdk/cmdline-tools
   cd ~/Android/Sdk/cmdline-tools
   # Скачать "Command line tools only" со страницы
   # https://developer.android.com/studio#command-tools , распаковать в latest/
   unzip commandlinetools-linux-*.zip -d latest_tmp && mv latest_tmp/cmdline-tools latest && rm -r latest_tmp
   ```

3. Переменные окружения (добавить в `~/.bashrc`/`~/.config/fish/config.fish`):
   ```bash
   export ANDROID_HOME="$HOME/Android/Sdk"
   export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
   ```
   Для fish (как в этом проекте — см. `fish_add_path` в конфиге,
   аналогично тому, как туда же добавлен Flutter):
   ```fish
   set -Ux ANDROID_HOME $HOME/Android/Sdk
   fish_add_path $ANDROID_HOME/cmdline-tools/latest/bin $ANDROID_HOME/platform-tools
   ```

4. Поставить нужные компоненты SDK и принять лицензии. Версию платформы
   берите строго ту, что зафиксирована как `compileSdkVersion` в этой
   версии Flutter (`android/app/build.gradle.kts` использует
   `flutter.compileSdkVersion` — сейчас это **36**; при обновлении
   Flutter SDK значение может измениться, проверить можно в
   `flutter/packages/flutter_tools/gradle/.../FlutterExtension.kt`):
   ```bash
   sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
   flutter doctor --android-licenses   # принять все (y)
   ```
   `minSdk` в проекте — 24 (Android 7.0), т.е. само приложение будет
   ставиться и работать на устройствах от Android 7.0, компиляция
   против API 36 на это не влияет. NDK отдельно ставить не обязательно — Flutter Gradle-плагин сам
   подтягивает версию, зафиксированную в `android/app/build.gradle.kts`
   (`ndkVersion = flutter.ndkVersion`), при первой сборке.

5. Проверить:
   ```bash
   flutter doctor -v
   ```
   Строка "Android toolchain" должна быть зелёной.

## 2. Сборка

```bash
cd /path/to/AudiLoc
flutter pub get

# APK для тестирования на конкретном устройстве/эмуляторе
flutter build apk --debug
# или сразу release (см. про подпись ниже)
flutter build apk --release

# App Bundle — то, что реально нужно для публикации в Google Play
flutter build appbundle --release

# Запуск на подключённом устройстве/эмуляторе с логами
flutter run -d <device-id>   # id устройств: `flutter devices`
```

Готовые файлы:
```
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/bundle/release/app-release.aab
```

### Первая сборка будет заметно дольше обычного

`audiotags` ([ADR 0002](adr/0002-audiotags-instead-of-id3.md)) собирает
Rust-код через `cargokit` под каждый целевой ABI (`arm64-v8a`,
`armeabi-v7a`, `x86_64` по умолчанию) — на первой сборке на новой
машине `cargokit` сам скачивает и кэширует Rust-тулчейн (нужен
интернет в этот момент), дальше пересобирает только изменившееся.
Отдельно ставить `rustup`/`cargo` не требуется.

## 3. Подпись release-сборки

Сейчас `android/app/build.gradle.kts` подписывает release debug-ключом
(`signingConfig = signingConfigs.getByName("debug")`) — этого
достаточно для локального тестирования release-сборки, но **не**
годится для публикации. Перед реальным релизом:

1. Сгенерировать keystore:
   ```bash
   keytool -genkey -v -keystore ~/audiloc-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias audiloc
   ```
2. Завести `android/key.properties` (не коммитить — добавить в
   `.gitignore`) со ссылкой на keystore и паролями.
3. Подключить `key.properties` в `android/app/build.gradle.kts` и
   заменить `signingConfig` release-варианта на новый —
   см. [официальный гайд Flutter по подписи Android-сборок](https://docs.flutter.dev/deployment/android#signing-the-app).

Это не сделано в текущем MVP-объёме — приложение не готово к
публикации в таком виде, только к локальной сборке/тестированию.

## 4. Разрешения (уже прописаны в манифесте)

`android/app/src/main/AndroidManifest.xml` уже содержит разрешения,
нужные реализованным на сегодня функциям:

| Разрешение | Зачем |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Встроенная передача файлов между устройствами (docs/adr/0010) и синк метаданных (`crdt_sync`) |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` | mDNS-обнаружение устройств в LAN (`bonsoir`) |
| `READ_MEDIA_AUDIO` (Android 13+), `READ_EXTERNAL_STORAGE` (до Android 12) | Чтение аудиофайлов из выбранной папки при импорте библиотеки |
| `POST_NOTIFICATIONS` | Задел под будущий `audio_service` (см. ниже) |

## 5. Известные ограничения

- **`READ_MEDIA_AUDIO` не запрашивается в рантайме.** На Android 13+
  одного объявления в манифесте недостаточно — приложение должно
  явно попросить разрешение у пользователя (например, через
  `permission_handler`). Это не реализовано: на Android 13+ импорт
  папки может увидеть 0 файлов, пока разрешение не выдано пользователем
  каким-то другим путём (вручную через настройки приложения). Роадмап-пункт.
- **`audio_service` подключён как зависимость, но не связан с
  плеером.** Для лок-скрин/Bluetooth-кнопок (ТЗ п.3) по-хорошему нужен
  `AudioHandler`-класс поверх `MediaKitPlayerService`, `MainActivity`
  должна наследоваться от `FlutterFragmentActivity` (сейчас — обычная
  `FlutterActivity`, см. `android/app/src/main/kotlin/.../MainActivity.kt`),
  плюс `<service>`/`<receiver>` в манифесте под `audio_service`. Ничего
  из этого не сделано — фоновое воспроизведение с системными
  элементами управления пока не работает, только пока приложение на
  экране. Отдельная задача на будущее.
Пункт про Syncthing как отдельный процесс (ранее — про foreground-сервис
для него) снят: встроенная передача файлов (docs/adr/0010) — это
обычный HTTP-сервер/клиент в самом процессе приложения, отдельного
системного сервиса не требует.
