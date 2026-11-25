# Install Kit — песочницы для ИИ-агентов в Kubernetes

Готовые, **настраиваемые** скрипты, чтобы поставить к себе в кластер четыре
технологии из доклада. Здесь только установка самих проектов — ничего из
бенчмарк-обвязки доклада. Каждый скрипт сделан по официальной документации
проекта и параметризуется переменными окружения (см. шапку каждого `install.sh`).

| Каталог | Что ставит | Способ (официальный) | Версия по умолчанию |
|---|---|---|---|
| [`agent-sandbox/`](agent-sandbox/) | **Agent Sandbox** (kubernetes-sigs) — оркестратор песочниц поверх `RuntimeClass` (gVisor/Kata) | `kubectl apply` релизного манифеста | `v1.0.12` |
| [`opensandbox/`](opensandbox/) | **OpenSandbox** (Agentic AI Foundation / Linux Foundation, ранее Alibaba) — продуктовый lifecycle-сервер + контроллер песочниц | Helm umbrella-чарт из чекаута релиза | `release-1.2.1` |
| [`agent-substrate/`](agent-substrate/) | **Agent Substrate** (начинался в Google, осенью 2026 принят в CNCF, tier Sandbox) — actor/worker-платформа со снапшотами и zero-trust | бинарь `ate-setup` + готовые образы из ghcr | `v1.0.0` |
| [`agent-substrate-ax/`](agent-substrate-ax/) | **Google AX** (Agent Executor) — декларативный слой задач ПОВЕРХ Agent Substrate | `make deploy` (сборка через `ko`) | `v0.3.1` ⚠️ |

> ⚠️ **Про версии.** Набор собран под те версии, на которых снимались числа в
> докладе. Область движется очень быстро: AX с тех пор переписали внутри (см.
> [`agent-substrate-ax/README.md`](agent-substrate-ax/README.md)), у Agent Sandbox
> релизы выходят примерно раз в неделю. Версия каждого проекта задаётся переменной,
> так что поставить свежую можно, но проверяйте официальную документацию проекта.

## Три слоя (для ориентации)
- **Слой 1 — изоляция:** runc / **gVisor** / microVM. Везде ниже мы берём **gVisor**.
- **Слой 2 — оркестратор песочниц:** Agent Sandbox, OpenSandbox, Agent Substrate.
- **Слой 3 — оркестратор задач:** Google AX (или свой harness; здесь — AX).

## Общие требования
- `kubectl` и доступ к кластеру (контекст задаётся переменной `CONTEXT`, по умолчанию — текущий).
- Для песочниц под **gVisor**: на нодах установлен `runsc` и в кластере есть
  `RuntimeClass` с именем `gvisor` (см. [gvisor.dev/docs](https://gvisor.dev/docs/user_guide/install/)
  и `RuntimeClass` ниже). Проверка: `kubectl get runtimeclass gvisor`.
- Для OpenSandbox — `helm` 3.x; для Agent Substrate / AX — `go` 1.27+ и `docker`.
- Все скрипты: `set -euo pipefail`, идемпотентны, **не хардкодят kube-контекст**,
  конфигурируются переменными окружения. Запуск: `ENV=значение ./install.sh`.
- **Выбор кластера.** Контекст задаётся переменной `CONTEXT`. Если её не задать и
  запустить в терминале, скрипт покажет список контекстов и спросит, с каким
  работать (Enter — текущий). Для автоматики задайте явно: `CONTEXT=kind-kind ./install.sh`.
- **Локальный kind.** Agent Sandbox и OpenSandbox ставятся на kind как есть (плюс
  `RuntimeClass gvisor`). Agent Substrate — с `KIND=true` (локальные хранилище
  снапшотов и реестр). AX — поверх Substrate, с `AX_SNAPSHOTS_BUCKET` и, за
  корпоративным прокси, `KO_DEFAULTBASEIMAGE` (см. `agent-substrate-ax/README.md`).

### Быстрый `RuntimeClass` для gVisor
```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
EOF
```