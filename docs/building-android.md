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

# APK для тестирования на конкретном устройстве/эмуляторе — debug-сборки
# не режут иконочный шрифт, флаг ниже им не нужен
flutter build apk --debug
# или сразу release (см. про подпись ниже). `--no-tree-shake-icons`
# обязателен для release/appbundle: без него у части Material-иконок
# (замечено на Icons.cast, Icons.cast_connected, Icons.smartphone,
# Icons.speaker_outlined) release-тришейкинг молча выкидывает глиф из
# шрифта, хотя иконка используется напрямую в коде
flutter build apk --release --no-tree-shake-icons

# App Bundle — то, что реально нужно для публикации в Google Play
flutter build appbundle --release --no-tree-shake-icons

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

`android/app/build.gradle.kts` уже настроен на реальную подпись:
читает `android/key.properties` (если файл существует) и подписывает
release-сборку им; если файла нет — молча откатывается на debug-ключ,
так что `flutter build apk --release` работает и без подписи, просто
для распространения (Google Play, прямая установка на чужое
устройство) не годится.

Keystore уже сгенерирован (`~/audiloc-release.jks`, alias `audiloc`).
Чтобы включить реальную подпись:

1. Открыть `android/key.properties` (уже заведён, gitignored — не
   коммитится, `android/.gitignore` это гарантирует) и заполнить два
   пароля (`storePassword`, `keyPassword` — те, что задавали при
   `keytool -genkey`):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=audiloc
   storeFile=/home/zaigard/audiloc-release.jks
   ```
2. Собрать как обычно — `flutter build apk --release` или
   `flutter build appbundle --release` теперь подписывают этим ключом
   автоматически, никаких дополнительных флагов не нужно.

Если `key.properties` нужно завести заново (потерян, новая машина) —
[официальный гайд Flutter по подписи Android-сборок](https://docs.flutter.dev/deployment/android#signing-the-app)
описывает тот же паттерн, которым тут всё уже подключено.

**Храните `~/audiloc-release.jks` и пароли к нему отдельно от
репозитория** (менеджер паролей, отдельный зашифрованный бэкап) — при
потере ключа обновить уже опубликованное в Google Play приложение
станет невозможно, придётся публиковать под новым `applicationId`.

## 4. Разрешения (уже прописаны в манифесте)

`android/app/src/main/AndroidManifest.xml` уже содержит разрешения,
нужные реализованным на сегодня функциям:

| Разрешение | Зачем |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Встроенная передача файлов между устройствами (docs/adr/0010) и синк метаданных (`crdt_sync`) |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` | mDNS-обнаружение устройств в LAN (`bonsoir`) |
| `READ_MEDIA_AUDIO` (Android 13+), `READ_EXTERNAL_STORAGE` (до Android 12) | Чтение аудиофайлов из выбранной папки при импорте библиотеки |
| `POST_NOTIFICATIONS`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | `audio_service` — уведомление воспроизведения, лок-скрин, кнопки гарнитуры (см. ниже) |

## 5. Лок-скрин / уведомление / кнопки гарнитуры

`AudilocAudioHandler` (`lib/services/playback/audiloc_audio_handler.dart`)
оборачивает существующий `PlayerService` для `audio_service` — сама
логика воспроизведения не меняется, просто её состояние ещё и
зеркалится наружу (уведомление, лок-скрин), а команды оттуда (в т.ч.
клик по кнопке на гарнитуре/Bluetooth-наушниках) приходят обратно в
тот же `PlayerService`. Включается только на Android
(`Platform.isAndroid` в `main.dart`) — у `audio_service` нет
Linux/Windows-реализации, `MainActivity` наследуется от
`AudioServiceActivity` вместо `FlutterActivity`, `<service>`/
`<receiver>` прописаны в манифесте. Проверено реальной сборкой
(`flutter build apk`), живая проверка на устройстве, что уведомление
и клик по кнопке гарнитуры действительно работают — ещё не сделана
(следующий шаг для пользователя после установки).

## 6. Известные ограничения

- **`READ_MEDIA_AUDIO` не запрашивается в рантайме.** На Android 13+
  одного объявления в манифесте недостаточно — приложение должно
  явно попросить разрешение у пользователя (например, через
  `permission_handler`). Это не реализовано: на Android 13+ импорт
  папки может увидеть 0 файлов, пока разрешение не выдано пользователем
  каким-то другим путём (вручную через настройки приложения). Роадмап-пункт.
