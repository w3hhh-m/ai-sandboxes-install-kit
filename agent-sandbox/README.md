# Agent Sandbox

Оркестратор песочниц (слой 2) от kubernetes-sigs (подпроект SIG Apps, начинался
в Google). Даёт CRD `Sandbox` — декларативный «одиночный stateful-под со стабильной
идентичностью», а изоляцию делегирует рантайму через `RuntimeClass` (gVisor/Kata).
Extensions добавляют `SandboxTemplate` / `SandboxWarmPool` / `SandboxClaim`
(шаблоны и warm-пул).

> **Сеть из коробки.** Вопреки репутации «минималистичного», проект ставит
> NetworkPolicy **по умолчанию**: у `SandboxTemplate` поле `networkPolicyManagement`
> имеет значение по умолчанию `Managed`. Политика закрывает приватные сети и
> облачную метадату, оставляя выход в интернет, и дополнительно выключает
> автомонтирование токена сервис-аккаунта. Чего в проекте нет — хранилища секретов.

- Сайт/доки: https://agent-sandbox.sigs.k8s.io/docs/
- Репозиторий: https://github.com/kubernetes-sigs/agent-sandbox
- Конфиг контроллера и тюнинг: `docs/configuration.md`, `docs/performance-tuning.md` в репо.

## Установка
```bash
./install.sh                       # v1.0.12, standard (core + extensions)
VERSION=v1.0.2 ./install.sh        # закрепить версию
MODE=core ./install.sh             # только Sandbox, без extensions
CONTEXT=my-cluster ./install.sh    # конкретный kube-контекст
DRY_RUN=true ./install.sh          # посмотреть без применения
```
Контроллер встаёт в namespace `agent-sandbox-system`. Способ — официальный
`kubectl apply` релизного манифеста (`sandbox-with-extensions.yaml`).

Переменные: `VERSION` (тег или `latest`), `MODE` (`standard|core|extensions`),
`CONTEXT`, `DRY_RUN`.

## Требования
- Kubernetes **1.25+** (рекомендуется **1.29+**); на 1.25–1.28 держите feature gate
  `CustomResourceValidationExpressions` включённым, иначе теряется CEL-валидация CRD.
- Для изоляции gVisor — `RuntimeClass` с именем `gvisor` и `runsc` на нодах
  (см. корневой [README](../README.md)).

## Проверка и примеры
```bash
kubectl get crd sandboxes.agents.x-k8s.io
kubectl get deploy agent-sandbox-controller -n agent-sandbox-system

kubectl apply -f examples/sandbox-gvisor.yaml    # одна песочница на gVisor
kubectl apply -f examples/warmpool.yaml          # шаблон + warm-пул + claim
```

## Снос
```bash
CONFIRM=yes ./uninstall.sh         # сначала запустите без CONFIRM — покажет используемые ресурсы
```
⚠️ Удаление CRD **каскадно** удаляет все `Sandbox`/`Claim`/`WarmPool` во всех namespace.

## Полезное
- **Sandbox Router** (опционально) — HTTP-прокси к подам песочниц, удобно для
  gVisor/Kata, где прямой port-forward недоступен: `sandbox-router/deploy/` в репо.
- **SDK**: Go — путь импорта `sigs.k8s.io/agent-sandbox/clients/go/sandbox` (это
  пакет внутри модуля `sigs.k8s.io/agent-sandbox`, версии совпадают с тегами репо);
  Python — `pip install k8s-agent-sandbox`.
- **Helm**: альтернатива `kubectl apply` — чарт в `helm/` репозитория (см. `helm/README.md`).
