# EliteGuard

iOS-приложение Элитный Сочи (iOS 26+): вход в Spark, заведение сотрудников EliteSIP и привязка машины к сотруднику сканированием QR-кода на экране клиента. Ключей активации нет: после привязки Spark сам присылает машине номер и настройки.

Протокол привязки — `docs/elitesip-qr-pair.md` в репозитории Spark.

## Сборка

```bash
xcodegen generate
open EliteGuard.xcodeproj
```

Проект описан в `project.yml`, `.xcodeproj` генерируется и в git не хранится.
