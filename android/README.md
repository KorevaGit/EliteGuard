# EliteGuard для Android

Нативное приложение на Kotlin и Jetpack Compose. Использует тот же Spark API, что и iOS-приложение.

## Открыть и собрать

1. В Android Studio выберите **Open** и папку `android`.
2. В **Settings → Build, Execution, Deployment → Build Tools → Gradle** выберите Gradle JDK 17. Если его нет, Android Studio предложит скачать его. Затем дождитесь синхронизации Gradle.
3. Выберите устройство с Android 8.0+ и нажмите **Run**.

Для сборки из терминала:

```sh
cd android
JAVA_HOME='/путь/к/JDK-17' ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :app:assembleDebug
```

APK появится в `app/build/outputs/apk/debug/`.

## Подписанный выпуск

Ключ выпуска хранится локально в `signing/EliteGuard-release.p12`, пароль и путь к нему — в `signing.properties`. Оба файла исключены из Git. Для повторной сборки используйте `./gradlew :app:assembleRelease`; готовый APK появится в `app/build/outputs/apk/release/`.

Сохраните **оба файла** в надёжном резервном хранилище. Без этого ключа нельзя будет выпускать обновления с той же подписью. Установленная debug-версия подписана другим ключом: перед установкой release-версии её потребуется удалить с устройства, что удалит локальные данные приложения.

Сканирование QR использует Google Code Scanner и требует Google Play services. Ссылку из QR можно вставить вручную на экране привязки, а шестизначный код можно ввести без камеры. Токены хранятся в зашифрованном виде с ключом Android Keystore.

Для проверки с настоящим Spark нужны тестовая учётная запись и машина EliteSIP, показывающая QR-код или шестизначный код. Версия Android пока не проверена на реальном сервере и устройстве.
