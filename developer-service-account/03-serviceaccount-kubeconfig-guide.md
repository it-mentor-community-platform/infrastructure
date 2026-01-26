### Инструкция: Создание ServiceAccount и генерация kubeconfig для разработчиков

#### Описание

Этот документ описывает процесс создания ServiceAccount с ограниченными правами доступа и генерации kubeconfig файлов для разработчиков.

**Цель:** 
- Предоставить разработчикам доступ к кластеру на уровне чтения
- Разрешить создание port-forward к postgres-client Pod
- Запретить изменение или удаление ресурсов кластера

---

### Требования к окружению

#### Необходимое ПО

- **kubectl** (версия 1.24+)
- **bash** (для выполнения скрипта)
- Доступ к интернету (для установки пакетов)

##### Установка kubectl

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Windows (WSL):**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

#### Права доступа к Kubernetes кластеру

**⚠️ КРИТИЧЕСКИ ВАЖНО:** Для выполнения данной инструкции требуются **права администратора кластера**.

##### Проверка текущих прав

```bash
# Проверить права на создание ServiceAccount
kubectl auth can-i create serviceaccounts --all-namespaces

# Проверить права на создание ClusterRole
kubectl auth can-i create clusterroles

# Проверить права на создание ClusterRoleBinding
kubectl auth can-i create clusterrolebindings

# Проверить права на создание токенов
kubectl auth can-i create serviceaccounts/token -n developers
```

**Все команды должны вернуть:** `yes`

Если хотя бы одна команда вернула `no` - **обратитесь к администратору кластера** для получения необходимых прав.

##### Требуемые RBAC права

Ваш kubeconfig должен иметь права на:
- Создание namespace
- Создание ServiceAccount в любом namespace
- Создание ClusterRole и ClusterRoleBinding
- Создание Role и RoleBinding в namespace `postgres`
- Создание токенов для ServiceAccount

**Рекомендуется:** Использовать kubeconfig с ClusterRole `cluster-admin` или эквивалентными правами.

##### Проверка подключения к кластеру

```bash
# Проверить что kubectl настроен
kubectl cluster-info

# Проверить доступ к API server
kubectl get nodes

# Проверить версию кластера
kubectl version
```

Если команды выполняются успешно - окружение готово к работе.

---

### Архитектура RBAC

```
ServiceAccount (developers namespace)
    ↓
ClusterRole (read-only на уровне кластера)
    ↓
ClusterRoleBinding
    +
Role (port-forward права в postgres namespace)
    ↓
RoleBinding
```

**Принципы:**
- ServiceAccount хранится в отдельном namespace `developers`
- Минимальные права на уровне кластера (только чтение namespaces)
- Специфичные права только в namespace `postgres`
- Срок действия токена: 1 год

---

### Структура проекта

```
infrastructure/
└── developer-service-account/
    ├── 03-serviceaccount-kubeconfig-guide.md
    ├── service-account.yaml
    ├── ClusterRole.yaml
    ├── ClusterRoleBinding.yaml
    ├── role.yaml
    ├── RoleBinding.yaml
    └── generate-developer-kubeconfig.sh
```

---

### Шаг 1: Создание namespace для ServiceAccounts

```bash
# Создать namespace для разработчиков
kubectl create namespace developers

# Проверить
kubectl get namespace developers
```

---

### Шаг 2: Создание RBAC ресурсов

##### ServiceAccount

**Файл: `service-account.yaml`**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: developer-user
  namespace: developers
```

##### ClusterRole (минимальные права на кластер)

**Файл: `ClusterRole.yaml`**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer-read-only
rules:
# Просмотр namespaces
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]

# Просмотр nodes (опционально)
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
```

##### ClusterRoleBinding

**Файл: `ClusterRoleBinding.yaml`**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: developer-read-only-binding
subjects:
- kind: ServiceAccount
  name: developer-user
  namespace: developers
roleRef:
  kind: ClusterRole
  name: developer-read-only
  apiGroup: rbac.authorization.k8s.io
```

##### Role (права в postgres namespace)

**Файл: `role.yaml`**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: postgres-port-forward
  namespace: postgres
rules:
# Права на просмотр pods
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]

# Права на просмотр логов
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]

# Права на port-forward
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create"]

# Права на просмотр services
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list"]
```

##### RoleBinding

**Файл: `RoleBinding.yaml`**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: postgres-port-forward-binding
  namespace: postgres
subjects:
- kind: ServiceAccount
  name: developer-user
  namespace: developers
roleRef:
  kind: Role
  name: postgres-port-forward
  apiGroup: rbac.authorization.k8s.io
```

---

### Шаг 3: Применение RBAC конфигурации

```bash
# Перейти в папку с манифестами
cd infrastructure/developer-service-account

# Применить все манифесты по порядку
kubectl apply -f service-account.yaml
kubectl apply -f ClusterRole.yaml
kubectl apply -f ClusterRoleBinding.yaml
kubectl apply -f role.yaml
kubectl apply -f RoleBinding.yaml
```

##### Проверка созданных ресурсов

```bash
# ServiceAccount
kubectl get serviceaccount -n developers

# ClusterRole
kubectl get clusterrole developer-read-only

# ClusterRoleBinding
kubectl get clusterrolebinding developer-read-only-binding

# Role
kubectl get role -n postgres

# RoleBinding
kubectl get rolebinding -n postgres
```

##### Проверка прав

```bash
# Проверить что ServiceAccount может видеть namespaces
kubectl auth can-i list namespaces \
  --as=system:serviceaccount:developers:developer-user
# Должно вернуть: yes

# Проверить право на port-forward
kubectl auth can-i get pods -n postgres \
  --as=system:serviceaccount:developers:developer-user
# Должно вернуть: yes

# Проверить отсутствие прав на удаление
kubectl auth can-i delete pods -n postgres \
  --as=system:serviceaccount:developers:developer-user
# Должно вернуть: no
```

---

### Шаг 4: Генерация kubeconfig для разработчиков

##### Скрипт генерации kubeconfig

**Файл: `generate-developer-kubeconfig.sh`**

```bash
#!/bin/bash

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Проверка аргументов
if [ -z "$1" ]; then
    echo -e "${RED}❌ Ошибка: Не указан email разработчика${NC}"
    echo ""
    echo "Использование: $0 <developer-email>"
    echo "Пример: $0 ivan.petrov@example.com"
    exit 1
fi

DEVELOPER_EMAIL="$1"
DEVELOPER_NAME=$(echo "$DEVELOPER_EMAIL" | cut -d'@' -f1 | tr '.' '-')

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📝 Генерация kubeconfig для разработчика${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Разработчик: ${YELLOW}$DEVELOPER_EMAIL${NC}"
echo ""

# Константы
SERVICE_ACCOUNT_NAME="developer-user"
SERVICE_ACCOUNT_NAMESPACE="developers"
OUTPUT_DIR="./kubeconfig-output"
OUTPUT_FILE="${OUTPUT_DIR}/kubeconfig-${DEVELOPER_NAME}.yaml"

mkdir -p "$OUTPUT_DIR"

# Проверка ServiceAccount
echo -e "${GREEN}▶ Шаг 1/5: Проверка ServiceAccount...${NC}"
if ! kubectl get serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$SERVICE_ACCOUNT_NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ ServiceAccount $SERVICE_ACCOUNT_NAME не найден${NC}"
    exit 1
fi
echo -e "${GREEN}✅ ServiceAccount найден${NC}"
echo ""

# Создание токена (1 год)
echo -e "${GREEN}▶ Шаг 2/5: Генерация токена...${NC}"
TOKEN=$(kubectl create token "$SERVICE_ACCOUNT_NAME" \
    -n "$SERVICE_ACCOUNT_NAMESPACE" \
    --duration=8760h)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ Не удалось создать токен${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Токен создан (срок действия: 1 год)${NC}"
echo ""

# Получение CA сертификата
echo -e "${GREEN}▶ Шаг 3/5: Получение CA сертификата...${NC}"
CA_CERT=$(kubectl config view --raw --minify --flatten \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

if [ -z "$CA_CERT" ]; then
    echo -e "${RED}❌ Не удалось получить CA сертификат${NC}"
    exit 1
fi
echo -e "${GREEN}✅ CA сертификат получен${NC}"
echo ""

# Получение API server
echo -e "${GREEN}▶ Шаг 4/5: Получение API сервера...${NC}"
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

if [ -z "$API_SERVER" ]; then
    echo -e "${RED}❌ Не удалось получить адрес API сервера${NC}"
    exit 1
fi
echo -e "${GREEN}✅ API сервер: ${YELLOW}$API_SERVER${NC}"
echo ""

# Генерация kubeconfig
echo -e "${GREEN}▶ Шаг 5/5: Создание kubeconfig...${NC}"
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
[ -z "$CLUSTER_NAME" ] && CLUSTER_NAME="kubernetes-cluster"

cat > "$OUTPUT_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA_CERT
    server: $API_SERVER
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    namespace: postgres
    user: $DEVELOPER_EMAIL
  name: developer-context
current-context: developer-context
users:
- name: $DEVELOPER_EMAIL
  user:
    token: $TOKEN
EOF

echo -e "${GREEN}✅ Kubeconfig создан: ${YELLOW}$OUTPUT_FILE${NC}"
echo ""

# Проверка
echo -e "${GREEN}▶ Проверка kubeconfig...${NC}"
if kubectl --kubeconfig="$OUTPUT_FILE" get namespaces &>/dev/null; then
    echo -e "${GREEN}✅ Kubeconfig работает!${NC}"
else
    echo -e "${RED}❌ Kubeconfig не работает${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}▶ Проверка прав...${NC}"

kubectl --kubeconfig="$OUTPUT_FILE" get pods -n postgres &>/dev/null && \
    echo -e "${GREEN}  ✅ Просмотр pods: OK${NC}" || \
    echo -e "${RED}  ❌ Просмотр pods: FAIL${NC}"

kubectl --kubeconfig="$OUTPUT_FILE" get services -n postgres &>/dev/null && \
    echo -e "${GREEN}  ✅ Просмотр services: OK${NC}" || \
    echo -e "${RED}  ❌ Просмотр services: FAIL${NC}"

DELETE_CHECK=$(kubectl --kubeconfig="$OUTPUT_FILE" auth can-i delete pods -n postgres || true)
if [[ "$DELETE_CHECK" == "no" ]]; then
    echo -e "${GREEN}  ✅ Ограничение delete: OK${NC}"
else
    echo -e "${YELLOW}  ⚠ Ограничение delete: WARNING${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Kubeconfig успешно создан!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📋 Следующие шаги:${NC}"
echo ""
echo -e "  1️⃣  Отправить файл разработчику:"
echo -e "     ${YELLOW}$OUTPUT_FILE${NC}"
echo ""
echo -e "  2️⃣  Разработчик должен разместить файл согласно инструкции:"
echo -e "     ${YELLOW}infrastructure/postgres/postgres-client/01-developer-guide.md${NC}"
echo ""
echo -e "${YELLOW}⚠️  Важно:${NC}"
echo -e "  • Срок действия токена: ${YELLOW}1 год${NC}"
echo -e "  • НЕ коммитить в Git!"
echo -e "  • Передавать по защищённым каналам"
echo ""
```

##### Использование скрипта

```bash
# Сделать скрипт исполняемым
chmod +x generate-developer-kubeconfig.sh

# Сгенерировать kubeconfig для разработчика
./generate-developer-kubeconfig.sh ivan.petrov@example.com

# Вывод будет в ./kubeconfig-output/kubeconfig-ivan-petrov.yaml
```

##### Массовая генерация

```bash
# Создать список разработчиков
cat > developers.txt <<EOF
ivan.petrov@example.com
maria.ivanova@example.com
alex.sidorov@example.com
EOF

# Сгенерировать для всех
while read email; do
    ./generate-developer-kubeconfig.sh "$email"
done < developers.txt
```

---

### Шаг 5: Передача kubeconfig разработчикам

##### Безопасная передача

**✅ Рекомендуется:**
- Зашифрованная корпоративная почта
- Защищённое хранилище (1Password, LastPass)
- Внутренний защищённый файловый сервер
- Slack Direct Message (временно)

**❌ НЕ использовать:**
- Публичные каналы
- Незащищённая почта
- Git репозитории
- Общедоступные файлообменники

##### Инструкции для разработчика

Вместе с kubeconfig отправить:
1. Файл `kubeconfig-<имя>.yaml`
2. Ссылку на инструкцию: `infrastructure/postgres/postgres-client/01-developer-guide.md`

---

### Безопасность

##### Минимизация прав

Текущие права разработчика:
- ✅ Просмотр namespaces (только список)
- ✅ Просмотр pods в postgres namespace
- ✅ Просмотр services в postgres namespace
- ✅ Создание port-forward к pods
- ❌ Удаление ресурсов
- ❌ Изменение ресурсов
- ❌ Создание новых ресурсов
- ❌ Доступ к secrets

##### Рекомендации

1. Использовать отдельные ServiceAccount для каждого разработчика
2. Регулярно ротировать токены (раз в год)
3. Аудировать использование через API server logs
4. Использовать NetworkPolicies для ограничения доступа Pod
5. Включить Pod Security Standards
