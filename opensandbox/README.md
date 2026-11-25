# OpenSandbox

Продуктовый оркестратор песочниц (слой 2): контроллер CRD + lifecycle REST-сервер (слой 3)
+ ingress-gateway, SDK на нескольких языках, снапшоты. CRD: `BatchSandbox`, `Pool`,
`SandboxSnapshot` (группа `sandbox.opensandbox.io`, версия `v1alpha1`).

Проект начинался в Alibaba, осенью 2026 перешёл в Agentic AI Foundation (фонд
Linux Foundation). Следы прежней принадлежности остались в именах пакетов
(`@alibaba-group/opensandbox`, Go-модули `github.com/alibaba/...`) и в реестре
образов по умолчанию.

- Репозиторий: https://github.com/opensandbox-group/OpenSandbox
- Гайд по деплою: `docs/deployment/index.md` (в репо) — порядок чартов, значения.
- Конфигурация сервера: `docs/getting-started/configuration.md`.

## Установка
Официальный способ — Helm **umbrella-чарт из чекаута релизного тега** (отдельные
пакеты чартов не публикуются). Скрипт сам скачивает чекаут.

```bash
# 1) скопируйте и при желании отредактируйте значения (реестр, gVisor, ресурсы):
cp values.example.yaml values.yaml

# 2) поставьте (нужен API-ключ сервера):
API_KEY='замените-меня' VALUES=values.yaml ./install.sh

# варианты:
INSECURE=true ./install.sh                 # быстрый тест без ключа
VERSION=release-1.2.1 NAMESPACE=opensandbox-system ./install.sh
ENABLE_FAST_SANDBOX=true ./install.sh       # Firecracker (нужен KVM на нодах)
SRC_DIR=/path/to/checkout ./install.sh      # использовать готовый чекаут
CONTEXT=my-cluster ./install.sh
```

Контрол-плейн встаёт в `opensandbox-system`, рабочие песочницы — в namespace
`opensandbox` (скрипт его создаёт). Порядок компонентов (base → controller →
ingress-gateway → server) umbrella-чарт разруливает сам.

### Реестр образов
Дефолт чарта — Aliyun-реестр. В `values.example.yaml` всё
переопределено на **Docker Hub** (`docker.io/opensandbox/<component>`). Доступен и
GHCR: `ghcr.io/opensandbox-group/opensandbox/<component>`. Меняете реестр — меняйте
во всех `image.repository` и в путях `execd`/`egress`/`image-committer` внутри `configToml`.

### gVisor
Включён в `configToml` блоком `[secure_runtime] type=gvisor, k8s_runtime_class=gvisor`
(см. `values.example.yaml`). Нужен `RuntimeClass gvisor` в кластере.
⚠️ Сетевую изоляцию (`networkPolicy`) OpenSandbox на gVisor дать **не может** —
egress-сайдкар требует nftables, которых в gVisor нет; это только для Kata.

## Требования
- Helm 3.x, `kubectl`, и `git` **или** `curl`+`tar`.
- Для gVisor — `RuntimeClass gvisor` и `runsc` на нодах.

## Проверка
```bash
kubectl -n opensandbox-system get pods
kubectl get crd | grep opensandbox.io
kubectl -n opensandbox-system port-forward svc/opensandbox-server 8080:80 &
curl -s localhost:8080/health
```

## Снос
```bash
./uninstall.sh                     # снять helm-релиз
DELETE_CRD=true ./uninstall.sh     # + удалить CRD и namespace (каскадно снесёт песочницы)
```

## Опциональное
- **CLI** `osb`: `pip install opensandbox-cli`. **SDK**: Python `pip install opensandbox`,
  Node `npm install @alibaba-group/opensandbox`. MCP-сервер: `pip install opensandbox-mcp`.
- **PostgreSQL** для персистентности сервера и **fast-sandbox** (Firecracker) —
  см. `docs/deployment/index.md`.
