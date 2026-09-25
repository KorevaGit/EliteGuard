# EliteGuard

iOS-приложение Элитный Сочи (iOS 26+): вход в Spark, выпуск ключей активации EliteSIP и привязка ключа к машине сканированием QR-кода на экране клиента.

Протокол привязки — `docs/elitesip-qr-pair.md` в репозитории Spark.

## Сборка

```bash
xcodegen generate
open EliteGuard.xcodeproj
```

Проект описан в `project.yml`, `.xcodeproj` генерируется и в git не хранится.
