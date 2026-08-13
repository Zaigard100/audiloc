# 0008. Vendored `audiotags` с патчем compileSdkVersion

## Контекст

При первой реальной Android-сборке (в Android Studio) выяснилось, что
`audiotags` 1.4.5 ([ADR 0002](0002-audiotags-instead-of-id3.md))
собственным `android/build.gradle` жёстко прописывает
`compileSdkVersion 31`, тогда как его же транзитивные AndroidX-зависимости
(`androidx.fragment`, `androidx.window`, `androidx.lifecycle-*` и др.)
требуют компиляции против API 34+. Сборка падает на
`:audiotags:checkDebugAarMetadata` с 20 однотипными ошибками. Проверено:
не пофикшено даже в `master` на GitHub на момент проверки — это
действующий баг апстрима, не наша конфигурация.

Заодно за один заход всплыла целая цепочка версийных нестыковок в
дефолтном шаблоне `flutter create` этой версии Flutter: AGP 9.1.0
(дефолт) ломает Kotlin-компиляцию у плагинов со старым
`org.jetbrains.kotlin.android` (`file_picker`, `audiotags`) — под
AGP 9's "built-in Kotlin" их `compileDebugKotlin`-задача просто
перестаёт существовать. Пришлось откатить AGP до 8.13.2, что в свою
очередь потянуло за собой Gradle 8.14.5 (несовместим с JDK 25 из
бандла Android Studio — использовался JDK 21) и Kotlin ≥2.2.20.

## Решение

- `android/settings.gradle.kts`: AGP закреплён на `8.13.2`, Kotlin
  Gradle Plugin — на `2.2.20`.
- `android/gradle/wrapper/gradle-wrapper.properties`: Gradle `8.14.5`.
- `flutter config --jdk-dir=/usr/lib/jvm/java-21-openjdk` — чтобы CLI
  и Android Studio использовали одну и ту же JDK для Gradle.
- `third_party/audiotags/` — копия пакета версии 1.4.5 с единственным
  изменением: `compileSdkVersion 31` → `36`. Подключена через
  `dependency_overrides` в `pubspec.yaml`.

## Последствия

- Патч живёт в репозитории, а не в `~/.pub-cache` — переживает
  `flutter clean`/переустановку зависимостей на любой машине,
  собирающей этот проект.
- **Убрать `dependency_overrides`, как только апстрим выпустит версию
  с починенным `compileSdkVersion`** — тогда `third_party/audiotags/`
  можно удалить целиком.
- AGP/Gradle/Kotlin теперь на версию-две старше "дефолта" от
  `flutter create` этого Flutter SDK — сознательный компромисс:
  стабильность и совместимость с реальными плагинами важнее самой
  свежей версии тулчейна. Если `file_picker`/`audiotags` в будущем
  смигрируют на built-in Kotlin (как их и просит предупреждение
  сборки), это ограничение снимется и можно будет вернуться на AGP 9+.
