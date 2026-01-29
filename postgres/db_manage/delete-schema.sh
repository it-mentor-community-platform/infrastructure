#!/bin/bash

#############################################################################
# PostgreSQL Schema Deleter (Selectel Edition)
# 
# Описание:
#   Удаляет PostgreSQL схему, Kubernetes Secret и выводит инструкцию
#   по удалению пользователя через панель Selectel.
#
# Использование:
#   ./delete-schema.sh <service_name> <environment>
#
# Примеры:
#   ./delete-schema.sh auth_service staging
#   ./delete-schema.sh profile_service prod
#############################################################################

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }

#############################################################################
# Проверка параметров
#############################################################################

SERVICE_NAME=$1
ENVIRONMENT=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$ENVIRONMENT" ]; then
  log_error "Недостаточно параметров!"
  echo ""
  echo "Использование: ./delete-schema.sh <service_name> <environment>"
  echo ""
  exit 1
fi

if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "prod" ]; then
  log_error "Окружение должно быть 'staging' или 'prod'"
  exit 1
fi

#############################################################################
# Формирование имён
#############################################################################

SCHEMA_NAME="${SERVICE_NAME}_${ENVIRONMENT}"
USER_APP="${SERVICE_NAME}_${ENVIRONMENT}_app"
SERVICE_NAME_DASHED=$(echo "$SERVICE_NAME" | tr '_' '-')
SECRET_NAME="postgres-${SERVICE_NAME_DASHED}-${ENVIRONMENT}-app"
K8S_NAMESPACE="postgres"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_warning "УДАЛЕНИЕ инфраструктуры для сервиса: ${CYAN}${SERVICE_NAME}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "⚠️  Будет удалено:"
echo ""
echo "  🗄️  PostgreSQL:"
echo -e "      Схема:        ${RED}${SCHEMA_NAME}${NC} (включая все таблицы)"
echo ""
echo "  🔐 Kubernetes:"
echo -e "      Secret:    ${RED}${SECRET_NAME}${NC}"
echo -e "      Namespace: ${RED}${K8S_NAMESPACE}${NC}"
echo ""
echo "  👤 Пользователь PostgreSQL:"
echo -e "      ${YELLOW}${USER_APP}${NC} (требуется удалить вручную через Selectel)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_warning "Это действие НЕОБРАТИМО! Все данные в схеме будут потеряны."
echo ""
read -p "Вы уверены? Введите 'yes' для подтверждения: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_warning "Операция отменена"
    exit 0
fi

#############################################################################
# Получение данных подключения
#############################################################################

log_info "Получение данных подключения..."

if ! kubectl get secret postgres-creds -n bastion &>/dev/null; then
    log_error "Secret 'postgres-creds' не найден"
    exit 1
fi

PGHOST=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.host}' | base64 -d)
PGPORT=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.port}' | base64 -d)
PGDATABASE=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.dbname}' | base64 -d)
PGUSER=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.user}' | base64 -d)
PGPASSWORD=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.password}' | base64 -d)

export PGPASSWORD

log_success "Данные получены"
echo ""

#############################################################################
# Удаление схемы
#############################################################################

log_info "Удаление схемы '$SCHEMA_NAME'..."

SQL_DROP=$(cat <<EOF
DROP SCHEMA IF EXISTS "$SCHEMA_NAME" CASCADE;
\echo 'Schema dropped'
EOF
)

echo "$SQL_DROP" | kubectl exec -i deployment/bastion -n bastion -- \
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" 2>&1 | grep -v "^psql" | grep -v "NOTICE"

if [ $? -eq 0 ]; then
    log_success "Схема '$SCHEMA_NAME' удалена"
else
    log_warning "Схема не найдена или уже удалена"
fi

echo ""

#############################################################################
# Информация о Kubernetes Secret
#############################################################################

log_info "Проверка Kubernetes Secret..."

if kubectl get secret "$SECRET_NAME" -n "$K8S_NAMESPACE" &>/dev/null; then
    log_warning "Secret '$SECRET_NAME' НЕ удаляется автоматически"
    echo ""
    echo "  📝 Если нужно удалить Secret вручную:"
    echo "     kubectl delete secret $SECRET_NAME -n $K8S_NAMESPACE"
    echo ""
else
    log_info "Secret '$SECRET_NAME' не найден"
fi

echo ""

#############################################################################
# Инструкция по удалению пользователя
#############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_warning "ТРЕБУЕТСЯ РУЧНОЕ ДЕЙСТВИЕ: Удалите пользователя через панель Selectel"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "👤 Пользователь: ${YELLOW}${USER_APP}${NC}"
echo ""
echo "Инструкция:"
echo ""
echo "  1️⃣  Откройте панель управления Selectel:"
echo "      my.selectel.ru → Cloud Platform → Managed Databases"
echo ""
echo "  2️⃣  Выберите ваш PostgreSQL кластер"
echo ""
echo -e "  3️⃣  Перейдите на вкладку ${CYAN}«Пользователи»${NC}"
echo ""
echo -e "  4️⃣  Найдите пользователя: ${YELLOW}${USER_APP}${NC}"
echo ""
echo "  5️⃣  Нажмите кнопку удаления (корзина)"
echo ""
echo "  6️⃣  Подтвердите удаление"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_success "Удаление завершено!"
echo ""
