# Google AX (Agent Executor) поверх Agent Substrate

AX — декларативный **слой задач** (слой 3) над Agent Substrate: примитивы
`Task` / `Workspace` / `Model` / `Gateway`. Манифесты выглядят как привычные
kubectl-овские, но **ресурсами Kubernetes не являются**: CRD для `ax.io/v1alpha1`
в проекте нет, объекты применяются своей CLI (`ax apply -f`) по gRPC и хранятся в
самом AX. Так сделано сознательно — коротких задач могут быть миллионы, и в etcd
их не кладут. `kubectl` нужен только для инфраструктурных манифестов.

> ⚠️ **Версия.** Эти скрипты ставят **v0.3.1** — ту версию, на которой снимались
> числа в докладе. Её архитектура: gRPC-сервер `ax-server`, очередь в Redis и
> отдельный `ax-controller`. Осенью 2026 AX заметно переписали: Redis и
> `ax-controller` убрали, состояние переехало в PostgreSQL, сборка образов ушла с
> `ko`. Если ставите свежий тег — смотрите `docs/installation.md` в репозитории,
> манифесты и make-цели там другие.

- Репозиторий: https://github.com/google/ax
- Интеграция с Substrate: README AX, раздел «Deploy the control plane».

> AX — ранняя референс-интеграция: версии v0.x, авторы сами предупреждают о
> breaking изменениях — и за пару месяцев переписали половину архитектуры.

## Нюанс 1: совместимость версий с Substrate (это главное)
AX собирается против конкретной версии Substrate (см. `go.mod`, зависимость
`github.com/agent-substrate/substrate`). Если версия вашего **развёрнутого**
Substrate отличается по wire-протоколу Control API, `ax-controller` не сможет
создать atespace/актор (задачи падают в `Failed` с ошибкой gRPC). Варианты:
- Поставить Substrate той версии/коммита, под которую собран ваш тег AX, **либо**
- Пересобрать клиентский слой AX к Substrate под вашу версию (AX не запинен на
  стабильный релиз Substrate). Начните с `go get github.com/agent-substrate/substrate@<ваша-версия>`
  в чекауте AX и поправьте `internal/substrate/client.go` под изменившийся API.

Проверка: после установки `ax apply -f examples/task.yaml && ax get tasks`.
Если `PHASE=Failed` с «connection/transport/proto» — это оно.

## Нюанс 2: зашитый бакет снапшотов
В `deploy/ax-controller.yaml` переменная `AX_SNAPSHOTS_BUCKET` по умолчанию
указывает на **внутренний dev-бакет Google** (`gs://...`). Задайте свой через
`AX_SNAPSHOTS_BUCKET=` при установке (скрипт сделает `kubectl set env`).

## Нюанс 3: доступ к Substrate Control API
`ax-controller` ходит в `api.ate-system.svc:443` своим ServiceAccount-токеном.
Нужно: (а) у Substrate в `ate-system` default-deny ingress — namespace AX надо
пометить `ate.dev/api-access=true` (политика `api` пускает на :443 из таких ns);
(б) выдать `system:serviceaccount:<ns>:ax-controller` роль owner на ateapi
(`kubectl ate create access-policy --global`). Скрипт делает оба шага при `GRANT=true`.

## Установка
```bash
# Substrate уже должен быть установлен (см. ../agent-substrate/).
AX_IMAGE_REPO=ghcr.io/ваш-аккаунт/ax \
AX_SNAPSHOTS_BUCKET=gs://ваш-bucket/ax/ \
KUBECTL_ATE=/usr/local/bin/kubectl-ate \
./install.sh

# варианты:
AX_VERSION=v0.3.1 NAMESPACE=ax-system ./install.sh
GRANT=false ./install.sh            # не настраивать доступ автоматически (сделаете сами)
SRC_DIR=~/ax ./install.sh           # сохранить чекаут (нужен для uninstall)
CONTEXT=my-cloud-cluster ./install.sh

# за корпоративным прокси, где cgr.dev отдаёт 403 (ko тянет оттуда базовый образ):
KO_DEFAULTBASEIMAGE=gcr.io/distroless/static:nonroot ./install.sh
```

`ko` по умолчанию берёт базовый образ с `cgr.dev` (chainguard static). Если эта
сеть его не пускает (403), задайте `KO_DEFAULTBASEIMAGE` на доступный static-образ
(например, `gcr.io/distroless/static:nonroot`). `AX_SNAPSHOTS_BUCKET` переопределяет
зашитый в манифест dev-бакет и обязателен на своём кластере/kind.
Переменные: `AX_IMAGE_REPO` (обязательна — реестр для ko), `AX_VERSION`,
`NAMESPACE`, `SUBSTRATE_NS`, `AX_SNAPSHOTS_BUCKET`, `GRANT`, `KUBECTL_ATE`,
`SRC_DIR`, `CONTEXT`.

## Требования
- Установленный и работающий **Agent Substrate** (`../agent-substrate/`).
- `ko` (https://ko.build) и реестр, из которого тянет кластер; `go`, `kubectl`,
  `git`/`curl`. Для шага доступа — `kubectl-ate` (собирается при установке Substrate).

## Проверка
```bash
kubectl -n ax-system get pods                 # ax-redis / ax-server / ax-controller
ax apply -f <checkout>/examples/task.yaml
ax get tasks                                  # PHASE должен дойти до Running
```

## Снос
```bash
SRC_DIR=~/ax ./uninstall.sh                   # Substrate не трогается
```
