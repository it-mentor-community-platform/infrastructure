#!/bin/bash

set -e

# ============================================================================
# Скрипт генерации kubeconfig для разработчиков
# ============================================================================
# 
# Использование: ./generate-developer-kubeconfig.sh <developer-email>
#
# Пример: ./generate-developer-kubeconfig.sh ivan.petrov@example.com
# ============================================================================

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# Создать директорию для вывода
mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Шаг 1: Проверка существования ServiceAccount
# ============================================================================
echo -e "${GREEN}▶ Шаг 1/5: Проверка ServiceAccount...${NC}"

if ! kubectl get serviceaccount "$SERVICE_ACCOUNT_NAME" -n "$SERVICE_ACCOUNT_NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ ServiceAccount $SERVICE_ACCOUNT_NAME не найден в namespace $SERVICE_ACCOUNT_NAMESPACE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ ServiceAccount найден${NC}"
echo ""

# ============================================================================
# Шаг 2: Создание токена (срок действия 1 год)
# ============================================================================
echo -e "${GREEN}▶ Шаг 2/5: Генерация токена...${NC}"

# Создать токен на 1 год (8760 часов)
TOKEN=$(kubectl create token "$SERVICE_ACCOUNT_NAME" \
    -n "$SERVICE_ACCOUNT_NAMESPACE" \
    --duration=8760h)

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ Не удалось создать токен${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Токен создан (срок действия: 1 год)${NC}"
echo ""

# ============================================================================
# Шаг 3: Получение CA сертификата кластера
# ============================================================================
echo -e "${GREEN}▶ Шаг 3/5: Получение CA сертификата кластера...${NC}"

# Получить CA сертификат из текущего kubeconfig
CA_CERT=$(kubectl config view --raw --minify --flatten \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

if [ -z "$CA_CERT" ]; then
    echo -e "${YELLOW}⚠ CA сертификат не найден в kubeconfig, попытка получить из ServiceAccount...${NC}"
    
    # Альтернативный способ - из secret ServiceAccount
    SECRET_NAME=$(kubectl get serviceaccount "$SERVICE_ACCOUNT_NAME" \
        -n "$SERVICE_ACCOUNT_NAMESPACE" \
        -o jsonpath='{.secrets[0].name}')
    
    if [ -n "$SECRET_NAME" ]; then
        CA_CERT=$(kubectl get secret "$SECRET_NAME" \
            -n "$SERVICE_ACCOUNT_NAMESPACE" \
            -o jsonpath='{.data.ca\.crt}')
    fi
    
    if [ -z "$CA_CERT" ]; then
        echo -e "${RED}❌ Не удалось получить CA сертификат${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ CA сертификат получен${NC}"
echo ""

# ============================================================================
# Шаг 4: Получение API сервера
# ============================================================================
echo -e "${GREEN}▶ Шаг 4/5: Получение адреса API сервера...${NC}"

API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

if [ -z "$API_SERVER" ]; then
    echo -e "${RED}❌ Не удалось получить адрес API сервера${NC}"
    exit 1
fi

echo -e "${GREEN}✅ API сервер: ${YELLOW}$API_SERVER${NC}"
echo ""

# ============================================================================
# Шаг 5: Генерация kubeconfig файла
# ============================================================================
echo -e "${GREEN}▶ Шаг 5/5: Создание kubeconfig файла...${NC}"

# Получить имя кластера
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')

if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="kubernetes-cluster"
fi

# Создать kubeconfig
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

echo -e "${GREEN}✅ Kubeconfig файл создан: ${YELLOW}$OUTPUT_FILE${NC}"
echo ""

# ============================================================================
# Проверка сгенерированного kubeconfig
# ============================================================================
echo -e "${GREEN}▶ Проверка kubeconfig...${NC}"

# Тест подключения
if kubectl --kubeconfig="$OUTPUT_FILE" get namespaces &>/dev/null; then
    echo -e "${GREEN}✅ Kubeconfig работает!${NC}"
else
    echo -e "${RED}❌ Kubeconfig не работает. Проверьте конфигурацию.${NC}"
    exit 1
fi

# Тест прав на port-forward
echo ""
echo -e "${GREEN}▶ Проверка прав...${NC}"

# Проверить pods
if kubectl --kubeconfig="$OUTPUT_FILE" get pods -n postgres &>/dev/null; then
    echo -e "${GREEN}  ✅ Просмотр pods: OK${NC}"
else
    echo -e "${RED}  ❌ Просмотр pods: FAIL${NC}"
fi

# Проверить services
if kubectl --kubeconfig="$OUTPUT_FILE" get services -n postgres &>/dev/null; then
    echo -e "${GREEN}  ✅ Просмотр services: OK${NC}"
else
    echo -e "${RED}  ❌ Просмотр services: FAIL${NC}"
fi

# Проверить что НЕТ прав на delete
DELETE_CHECK=$(kubectl --kubeconfig="$OUTPUT_FILE" auth can-i delete pods -n postgres || true)
if [ "$DELETE_CHECK" = "no" ]; then
    echo -e "${GREEN}  ✅ Ограничение delete: OK (нет прав)${NC}"
else
    echo -e "${YELLOW}  ⚠ Ограничение delete: WARNING (есть права!)${NC}"
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
echo -e "  2️⃣  Разработчик должен скопировать файл в ~/.kube/config:"
echo -e "     ${YELLOW}cp $OUTPUT_FILE ~/.kube/config${NC}"
echo ""
echo -e "  3️⃣  Или использовать через переменную окружения:"
echo -e "     ${YELLOW}export KUBECONFIG=$(pwd)/$OUTPUT_FILE${NC}"
echo ""
echo -e "  4️⃣  Проверить доступ:"
echo -e "     ${YELLOW}kubectl get pods -n postgres${NC}"
echo ""
echo -e "  5️⃣  Создать port-forward:"
echo -e "     ${YELLOW}kubectl port-forward -n postgres svc/postgres-client 5432:5432${NC}"
echo ""
echo -e "${YELLOW}⚠️  Важно:${NC}"
echo -e "  • Срок действия токена: ${YELLOW}1 год${NC}"
echo -e "  • После истечения - сгенерировать новый kubeconfig"
echo -e "  • НЕ коммитить файл в Git!"
echo -e "  • Передавать только по защищённым каналам"
echo ""
