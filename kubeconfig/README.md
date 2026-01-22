### Создание Service Account, RBAC и Kubeconfig в Kubernetes

#### Описание

Данная инструкция описывает процесс создания Service Account с настраиваемыми правами доступа (RBAC) и генерацию kubeconfig файла для использования этим аккаунтом. В качестве примера мы создадим readonly service account (`dev-readonly`) с правами на просмотр статусов подов во всех namespace без возможности модификации ресурсов.

#### Предварительные требования

- Доступ к Kubernetes кластеру через kubeconfig (скачан из панели Selectel)
- Установленный kubectl
- Права cluster-admin для создания ClusterRole и ClusterRoleBinding

#### Архитектура решения

```
ServiceAccount (dev-readonly)
    ↓
ClusterRoleBinding
    ↓
ClusterRole (readonly-all-namespaces)
    ↓
Permissions: get, list, watch pods (all namespaces)
```

---

#### Шаг 1: Создание Service Account

Service Account создается в namespace `kube-system` для централизованного управления.

**Создайте файл `01-serviceaccount.yaml`:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dev-readonly
  namespace: kube-system
```

**Примените манифест:**

```bash
kubectl apply -f 01-serviceaccount.yaml
```

**Проверьте создание:**

```bash
kubectl get serviceaccount dev-readonly -n kube-system
```

---

#### Шаг 2: Создание ClusterRole с кастомными правами

ClusterRole определяет разрешения на уровне всего кластера. В данном примере создаем readonly права для просмотра подов.

**Создайте файл `02-clusterrole.yaml`:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: readonly-all-namespaces
rules:
# Доступ к подам (просмотр)
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/status"]
  verbs: ["get", "list", "watch"]

# Доступ к другим основным ресурсам (опционально, раскомментируйте если нужно)
# - apiGroups: [""]
#   resources: ["services", "endpoints", "configmaps"]
#   verbs: ["get", "list", "watch"]

# Доступ к deployments, replicasets (опционально)
# - apiGroups: ["apps"]
#   resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
#   verbs: ["get", "list", "watch"]

# Доступ к ingress (опционально)
# - apiGroups: ["networking.k8s.io"]
#   resources: ["ingresses"]
#   verbs: ["get", "list", "watch"]

# Доступ к namespaces (для просмотра списка namespace)
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]
```

**Примените манифест:**

```bash
kubectl apply -f 02-clusterrole.yaml
```

**Проверьте создание:**

```bash
kubectl get clusterrole readonly-all-namespaces
kubectl describe clusterrole readonly-all-namespaces
```

---

#### Шаг 3: Создание ClusterRoleBinding

ClusterRoleBinding связывает Service Account с ClusterRole, предоставляя права.

**Создайте файл `03-clusterrolebinding.yaml`:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: dev-readonly-binding
subjects:
- kind: ServiceAccount
  name: dev-readonly
  namespace: kube-system
roleRef:
  kind: ClusterRole
  name: readonly-all-namespaces
  apiGroup: rbac.authorization.k8s.io
```

**Примените манифест:**

```bash
kubectl apply -f 03-clusterrolebinding.yaml
```

**Проверьте создание:**

```bash
kubectl get clusterrolebinding dev-readonly-binding
kubectl describe clusterrolebinding dev-readonly-binding
```

---

#### Шаг 4: Создание долгоживущего токена для Service Account

Начиная с Kubernetes 1.24+, токены для Service Account не создаются автоматически. Необходимо создать Secret с токеном вручную.

**Создайте файл `04-token-secret.yaml`:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dev-readonly-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: dev-readonly
type: kubernetes.io/service-account-token
```

**Примените манифест:**

```bash
kubectl apply -f 04-token-secret.yaml
```

**Дождитесь создания токена (несколько секунд):**

```bash
kubectl get secret dev-readonly-token -n kube-system
```

**Извлеките токен:**

```bash
# Сохраните токен в переменную
TOKEN=$(kubectl get secret dev-readonly-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)

# Проверьте что токен получен (должна быть длинная строка)
echo $TOKEN
```

---

#### Шаг 5: Генерация kubeconfig для Service Account

Получите данные текущего кластера из вашего admin kubeconfig.

**Получите параметры кластера:**

```bash
# Имя кластера
CLUSTER_NAME=$(kubectl config view -o jsonpath='{.clusters[0].name}')
echo "Cluster Name: $CLUSTER_NAME"

# API Server URL
CLUSTER_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
echo "Cluster Server: $CLUSTER_SERVER"

# Certificate Authority Data
CLUSTER_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
echo "CA Data (first 50 chars): ${CLUSTER_CA:0:50}..."
```

**Создайте kubeconfig файл:**

```bash
# Создайте файл dev-readonly-kubeconfig.yaml
cat > dev-readonly-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: dev-readonly
    namespace: default
  name: dev-readonly-context
current-context: dev-readonly-context
users:
- name: dev-readonly
  user:
    token: ${TOKEN}
EOF

echo "Kubeconfig создан: dev-readonly-kubeconfig.yaml"
```

**Проверьте созданный kubeconfig:**

```bash
# Проверьте структуру файла
cat dev-readonly-kubeconfig.yaml

# Проверьте размер файла (должен быть ~2-3 КБ)
ls -lh dev-readonly-kubeconfig.yaml
```

---

#### Шаг 6: Тестирование kubeconfig

Проверьте работоспособность созданного kubeconfig с ограниченными правами.

**Тест 1: Просмотр подов (должен работать)**

```bash
kubectl --kubeconfig=dev-readonly-kubeconfig.yaml get pods --all-namespaces
```

**Ожидаемый результат:** Список подов из всех namespace.

**Тест 2: Просмотр логов пода (должен работать)**

```bash
# Замените на реальное имя пода и namespace
kubectl --kubeconfig=dev-readonly-kubeconfig.yaml logs <pod-name> -n <namespace>
```

**Тест 3: Попытка создания ресурса (должна быть отклонена)**

```bash
kubectl --kubeconfig=dev-readonly-kubeconfig.yaml run test-pod --image=nginx
```

**Ожидаемый результат:** Ошибка доступа `Error from server (Forbidden)`

**Тест 4: Попытка удаления пода (должна быть отклонена)**

```bash
kubectl --kubeconfig=dev-readonly-kubeconfig.yaml delete pod <pod-name> -n <namespace>
```

**Ожидаемый результат:** Ошибка доступа `Error from server (Forbidden)`

**Тест 5: Просмотр namespace (должен работать)**

```bash
kubectl --kubeconfig=dev-readonly-kubeconfig.yaml get namespaces
```

---

#### Шаг 7: Передача kubeconfig

**Инструкции для пользователя:**

Передайте пользователю следующие инструкции по использованию kubeconfig:

```markdown
# Использование readonly kubeconfig

## Установка

1. Сохраните файл `dev-readonly-kubeconfig.yaml` в безопасное место
2. Установите переменную окружения:

### Linux/macOS:
export KUBECONFIG=~/dev-readonly-kubeconfig.yaml

### Windows PowerShell:
$env:KUBECONFIG="C:\path\to\dev-readonly-kubeconfig.yaml"

## Использование

# Просмотр подов во всех namespace
kubectl get pods --all-namespaces

# Просмотр подов в конкретном namespace
kubectl get pods -n production

# Просмотр логов
kubectl logs <pod-name> -n <namespace>

# Просмотр статуса пода
kubectl describe pod <pod-name> -n <namespace>

## Ограничения

- Только чтение (read-only)
- Нельзя создавать, изменять или удалять ресурсы
- Доступ ко всем namespace
```

---

#### Управление жизненным циклом

##### Отзыв доступа

Для отзыва доступа у пользователя:

```bash
# Удалите Secret с токеном (токен станет недействительным)
kubectl delete secret dev-readonly-token -n kube-system

# Или удалите ClusterRoleBinding (отключит все права)
kubectl delete clusterrolebinding dev-readonly-binding
```

##### Ротация токена

Для обновления токена:

```bash
# 1. Удалите старый Secret
kubectl delete secret dev-readonly-token -n kube-system

# 2. Создайте новый Secret
kubectl apply -f 04-token-secret.yaml

# 3. Получите новый токен
TOKEN=$(kubectl get secret dev-readonly-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)

# 4. Сгенерируйте новый kubeconfig (повторите Шаг 5)
```

##### Создание дополнительных пользователей с теми же правами

Для создания дополнительных пользователей с аналогичными правами:

```bash
# Создайте новый ServiceAccount с другим именем
kubectl create serviceaccount dev-readonly-user2 -n kube-system

# Добавьте его в существующий ClusterRoleBinding
kubectl patch clusterrolebinding dev-readonly-binding --type='json'   -p='[{"op": "add", "path": "/subjects/-", "value": {"kind": "ServiceAccount", "name": "dev-readonly-user2", "namespace": "kube-system"}}]'

# Создайте Secret для нового SA
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: dev-readonly-user2-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: dev-readonly-user2
type: kubernetes.io/service-account-token
EOF

# Сгенерируйте kubeconfig для нового пользователя (повторите Шаг 5)
```

---

#### Расширение прав (опционально)

Если нужно дать доступ к дополнительным ресурсам, отредактируйте ClusterRole:

```bash
kubectl edit clusterrole readonly-all-namespaces
```

Добавьте нужные ресурсы в секцию `rules`:

```yaml
# Пример: добавить доступ к services
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]

# Пример: добавить доступ к deployments
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
```


---

#### Безопасность

##### Минимальные привилегии

Текущая конфигурация предоставляет только read-only доступ к подам. Если нужны более строгие ограничения:

- Используйте `Role` вместо `ClusterRole` для ограничения доступа к конкретным namespace
- Ограничьте доступ только к подам (без логов): удалите `pods/log` из resources
- Используйте NetworkPolicy для ограничения сетевого доступа подов с этим ServiceAccount

---

#### Заключение

После выполнения всех шагов у вас будет:

1. ✅ Service Account `dev-readonly` с ограниченными правами
2. ✅ ClusterRole `readonly-all-namespaces` с read-only доступом
3. ✅ ClusterRoleBinding связывающий SA и Role
4. ✅ Долгоживущий токен в Secret
5. ✅ Kubeconfig файл `dev-readonly-kubeconfig.yaml` для пользователей

В примере с readonly доступом пользователи смогут:
- ✅ Просматривать статусы подов во всех namespace
- ✅ Читать логи подов
- ✅ Просматривать список namespace
- ❌ **НЕ** смогут создавать, изменять или удалять ресурсы

---

#### Быстрая справка команд

```bash
# Применить все манифесты
kubectl apply -f 01-serviceaccount.yaml
kubectl apply -f 02-clusterrole.yaml
kubectl apply -f 03-clusterrolebinding.yaml
kubectl apply -f 04-token-secret.yaml

# Получить токен
TOKEN=$(kubectl get secret dev-readonly-token -n kube-system -o jsonpath='{.data.token}' | base64 --decode)

# Получить параметры кластера
CLUSTER_NAME=$(kubectl config view -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Создать kubeconfig
cat > dev-readonly-kubeconfig.yaml <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    user: dev-readonly
    namespace: default
  name: dev-readonly-context
current-context: dev-readonly-context
users:
- name: dev-readonly
  user:
    token: ${TOKEN}
EOF

# Тестирование
kubectl --kubeconfig=dev-readonly-kubeconfig.yaml get pods --all-namespaces
```
