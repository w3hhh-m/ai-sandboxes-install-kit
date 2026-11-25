# Agent Substrate

Платформа нового типа: агент — это **actor**, который
мультиплексируется на пул **worker**-подов; простаивающие акторы усыпляются в
снапшоты. Плюс zero-trust (SPIFFE-идентичность каждого актора, default-deny сеть,
egress через шлюз). Тяжёлый контрол-плейн (Postgres, объект-стор, Envoy, трейсинг).

- Репозиторий: https://github.com/agent-substrate/substrate
- Инсталлятор: `cmd/ate-setup` (README там же), команды — `cmd/ate-setup/commands.md`.

## Предварительные требования (важно для облачного кластера)
Это не «apply и готово» — Substrate требует подготовленного кластера.

1. **Feature gates на kube-apiserver.** Нужны (по умолчанию выключены вплоть до
   Kubernetes 1.36):
   - `ClusterTrustBundle`, `ClusterTrustBundleProjection`, `PodCertificateRequest`
   - runtime-config `certificates.k8s.io/v1beta1=true`

   Включаются флагами apiserver: `--feature-gates=ClusterTrustBundle=true,ClusterTrustBundleProjection=true,PodCertificateRequest=true`
   и `--runtime-config=certificates.k8s.io/v1beta1=true`. На self-managed кластере —
   в манифесте apiserver / kubeadm. На managed (GKE/EKS/AKS) проверьте, что провайдер
   позволяет включить эти гейты; без них установка не поднимется (нет zero-trust
   идентичности актора).

2. **Объект-хранилище для снапшотов** — `SNAPSHOT_LOCATION`, например
   `gs://ВАШ_BUCKET/substrate/` или `s3://ВАШ_BUCKET/substrate/`. Должно быть
   читаемо/записываемо из кластера (на GKE — рабочая identity/Workload Identity;
   на других — доступ к S3-совместимому стору).

3. **Реестр образов**, читаемый из кластера. По умолчанию публичный
   `ghcr.io/agent-substrate/substrate` (anon pull). Можно зеркалировать в свой.

4. **gVisor** на нодах (`runsc`) — для `--sandbox-classes=gvisor`. microVM
   (`gvisor,microvm`) требует KVM на нодах и на managed-кластерах обычно недоступен.

## Установка
```bash
# Облачный/обычный кластер — нужен внешний объект-стор под снапшоты:
SNAPSHOT_LOCATION=gs://your-bucket/substrate/ ./install.sh

# Локальный kind — хранилище и реестр поднимаются сами (KIND=true):
KIND=true ./install.sh
CONTEXT=kind-kind KIND=true ./install.sh

# варианты:
VERSION=v1.0.0 IMAGE_REPO=ghcr.io/agent-substrate/substrate ./install.sh
SNAPSHOT_LOCATION=s3://your-bucket/substrate/ SANDBOX_CLASSES=gvisor ./install.sh
INGRESS_SPIFFE='spiffe://cluster.local/ns/ate-system/sa/atenet-client,spiffe://cluster.local/ns/myapp/sa/caller' ./install.sh
EXTRA_ARGS='--ateapi-postgres-storage-class fast-ssd' ./install.sh   # доп. флаги ate-setup
CONTEXT=my-cloud-cluster ./install.sh
SRC_DIR=~/substrate ./install.sh    # сохранить чекаут (нужен для uninstall)
```
Скрипт скачивает чекаут релиза, собирает `ate-setup` и `kubectl-ate` (Go 1.27
подтянется сам), затем `ate-setup deploy` ставит контроль-плейн из готовых образов.

Ключевые переменные: `SNAPSHOT_LOCATION` (для облака обязательна), `KIND`
(локальный kind: `ate-setup --kind` сам даёт хранилище и реестр), `VERSION`,
`IMAGE_REPO`, `NAMESPACE`, `SANDBOX_CLASSES`, `INGRESS_SPIFFE`, `CRED_PROVIDER`,
`EXTRA_ARGS`, `CONTEXT`, `SRC_DIR`. Полный список флагов: `ate-setup deploy --help`.

**KIND=true** дополнительно поднимает локальный `kind-registry` (порт 5001 →
`kind-registry:5000` на нодах) и передаёт `ate-setup --kind` вместо
`--snapshot-location`. Снос: `CONTEXT=kind-kind KIND=true SRC_DIR=… ./uninstall.sh`.

## Доступ к акторам
Клиенты достукиваются до акторов только через ingress-router по SPIFFE mTLS
(не напрямую по pod-IP). Разрешите свой клиент в `INGRESS_SPIFFE`. CLI:
```bash
kubectl ate create actor my-actor -a <atespace> --template <tmpl>
kubectl ate proxy actor my-actor -a <atespace>        # локальный прокси к актору
```

## Проверка
```bash
kubectl -n ate-system get pods           # все Running
kubectl get crd | grep ate.dev           # workerpools/sandboxconfigs/...
kubectl ate get atespace
```

## Снос
```bash
SRC_DIR=~/substrate ./uninstall.sh       # нужен тот же чекаут (bin/ate-setup)
```

## Замечание про локальный тест
Для быстрой локальной пробы у проекта есть собственный quickstart, который сам
поднимает тестовый кластер и встроенное хранилище — см. раздел Quickstart в README
репозитория. Эти скрипты рассчитаны на **ваш рабочий кластер** и внешнее хранилище.
