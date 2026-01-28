#!/bin/bash

#############################################################################
# PostgreSQL Schema and User Creator (Selectel Edition)
#
# Описание:
# Автоматически создаёт PostgreSQL схему, выдаёт права пользователю
# (созданному через панель Selectel) и создаёт Kubernetes Secret.
#
# Использование:
# ./create-schema.sh <service_name> <environment>
#
# Примеры:
# ./create-schema.sh auth_service staging
# ./create-schema.sh profile_service prod
#
# Требования:
# - kubectl с доступом к кластеру
# - Kubernetes Secret 'postgres-creds' в namespace 'bastion'
# - Доступ к веб-панели Selectel для создания пользователей
#############################################################################

set -e # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для вывода с цветом
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

log_action() {
    echo -e "${MAGENTA}👉${NC} $1"
}

log_step() {
    echo -e "${CYAN}▶${NC} $1"
}

#############################################################################
# Проверка параметров
#############################################################################

SERVICE_NAME=$1
ENVIRONMENT=$2

if [ -z "$SERVICE_NAME" ] || [ -z "$ENVIRONMENT" ]; then
    log_error "Недостаточно параметров!"
    echo ""
    echo "Использование: ./create-schema.sh <service_name> <environment>"
    echo ""
    echo "Параметры:"
    echo "  service_name - имя сервиса (например: auth_service, profile_service)"
    echo "  environment  - окружение: staging или prod"
    echo ""
    echo "Примеры:"
    echo "  ./create-schema.sh auth_service staging"
    echo "  ./create-schema.sh profile_service prod"
    echo ""
    exit 1
fi

# Проверка допустимых окружений
if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "prod" ]; then
    log_error "Окружение должно быть 'staging' или 'prod'"
    exit 1
fi

#############################################################################
# Формирование имён согласно конвенции
#############################################################################

SCHEMA_NAME="${SERVICE_NAME}_${ENVIRONMENT}"
USER_APP="${SERVICE_NAME}_${ENVIRONMENT}_app"

# Для Secret заменяем подчёркивания на дефисы
SERVICE_NAME_DASHED=$(echo "$SERVICE_NAME" | tr '_' '-')
SECRET_NAME="postgres-${SERVICE_NAME_DASHED}-${ENVIRONMENT}-app"
K8S_NAMESPACE="postgres"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Создание инфраструктуры для сервиса: ${CYAN}${SERVICE_NAME}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Будет создано:"
echo ""
echo "  🗄️  PostgreSQL:"
echo -e "     Схема:        ${CYAN}${SCHEMA_NAME}${NC}"
echo -e "     Пользователь: ${CYAN}${USER_APP}${NC}"
echo ""
echo "  🔐 Kubernetes:"
echo -e "     Secret:    ${CYAN}${SECRET_NAME}${NC}"
echo -e "     Namespace: ${CYAN}${K8S_NAMESPACE}${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Подтверждение
read -p "Продолжить? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "Операция отменена пользователем"
    exit 0
fi

#############################################################################
# Получение данных подключения из Kubernetes Secret
#############################################################################

log_step "Шаг 1/5: Получение данных подключения к PostgreSQL..."
echo ""

# Проверка наличия Secret
if ! kubectl get secret postgres-creds -n bastion &>/dev/null; then
    log_error "Secret 'postgres-creds' не найден в namespace 'bastion'"
    log_error "Убедитесь, что бастион настроен и Secret создан"
    exit 1
fi

PGHOST=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.host}' 2>/dev/null | base64 -d)
PGPORT=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.port}' 2>/dev/null | base64 -d)
PGDATABASE=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.dbname}' 2>/dev/null | base64 -d)
PGUSER=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.user}' 2>/dev/null | base64 -d)
PGPASSWORD=$(kubectl get secret postgres-creds -n bastion -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [ -z "$PGHOST" ] || [ -z "$PGPASSWORD" ]; then
    log_error "Не удалось получить данные подключения из Secret"
    exit 1
fi

log_success "Данные подключения получены"
echo "  Host: $PGHOST"
echo "  User: $PGUSER"
echo ""

export PGPASSWORD

#############################################################################
# Проверка существования пользователя (ТЕПЕРЬ ШАГ 2!)
#############################################################################

log_step "Шаг 2/5: Проверка пользователя PostgreSQL..."
echo ""

USER_EXISTS=$(kubectl exec -i deployment/bastion -n bastion -- \
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname = '$USER_APP';" 2>/dev/null)

USER_ALREADY_EXISTS=false
UPDATE_PASSWORD=false
SKIP_USER_CREATION=false

if [ "$USER_EXISTS" = "1" ]; then
    USER_ALREADY_EXISTS=true
    log_warning "Пользователь '$USER_APP' уже существует"
    echo ""
    read -p "Обновить пароль пользователя? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        UPDATE_PASSWORD=true
    else
        log_info "Пароль не будет обновлён. Продолжаем с выдачей прав..."
        SKIP_USER_CREATION=true
    fi
fi

#############################################################################
# Инструкция по созданию пользователя через Selectel (если не существует)
#############################################################################

if [ "$USER_ALREADY_EXISTS" = false ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warning "ТРЕБУЕТСЯ РУЧНОЕ ДЕЙСТВИЕ: Создайте пользователя через панель Selectel"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${YELLOW}⚠️  В Selectel Managed Databases пользователи создаются только через веб-панель.${NC}"
    echo ""
    log_action "Инструкция по созданию пользователя:"
    echo ""
    echo "  1️⃣  Откройте панель управления Selectel:"
    echo "     my.selectel.ru → Cloud Platform → Managed Databases"
    echo ""
    echo "  2️⃣  Выберите ваш PostgreSQL кластер"
    echo ""
    echo -e "  3️⃣  Перейдите на вкладку ${CYAN}«Пользователи»${NC}"
    echo ""
    echo -e "  4️⃣  Нажмите кнопку ${CYAN}«Создать пользователя»${NC}"
    echo ""
    echo "  5️⃣  Заполните форму:"
    echo "     ┌─────────────────────────────────────────────────┐"
    echo -e "     │ Имя пользователя: ${GREEN}${USER_APP}${NC}"
    echo -e "     │ Пароль:           ${YELLOW}[придумайте надёжный пароль]${NC}"
    echo "     └─────────────────────────────────────────────────┘"
    echo ""
    echo -e "  6️⃣  Выдайте доступ к базе данных:"
    echo -e "     В разделе ${CYAN}«Имеют доступ»${NC} выберите базу: ${GREEN}${PGDATABASE}${NC}"
    echo ""
    echo -e "  7️⃣  Нажмите ${CYAN}«Создать»${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_warning "Скрипт приостановлен. После создания пользователя нажмите Enter..."
    read -p ""
fi

#############################################################################
# Запрос пароля пользователя
#############################################################################

PASSWORD_APP=""
if [ "$SKIP_USER_CREATION" = false ]; then
    echo ""
    if [ "$UPDATE_PASSWORD" = true ]; then
        log_info "Введите ${YELLOW}новый${NC} пароль для пользователя ${CYAN}${USER_APP}${NC}:"
    else
        log_info "Введите пароль пользователя ${CYAN}${USER_APP}${NC}:"
    fi
    echo ""
    read -s -p "Пароль: " PASSWORD_APP
    echo ""
    if [ -z "$PASSWORD_APP" ]; then
        log_error "Пароль не может быть пустым"
        exit 1
    fi
    log_success "Пароль получен"
    echo ""
fi

#############################################################################
# Обновление пароля (если пользователь существует и выбрано обновление)
#############################################################################

if [ "$UPDATE_PASSWORD" = true ]; then
    log_info "Обновление пароля пользователя в Selectel..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warning "ТРЕБУЕТСЯ РУЧНОЕ ДЕЙСТВИЕ: Обновите пароль через панель Selectel"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_action "Инструкция:"
    echo ""
    echo "  1️⃣  Откройте панель Selectel → Managed Databases → ваш кластер"
    echo -e "  2️⃣  Вкладка «Пользователи» → найдите ${CYAN}${USER_APP}${NC}"
    echo "  3️⃣  Нажмите на пользователя для редактирования"
    echo "  4️⃣  Обновите пароль на тот, что вы только что ввели"
    echo "  5️⃣  Сохраните изменения"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_warning "После обновления пароля нажмите Enter..."
    read -p ""
    echo ""
fi

#############################################################################
# Проверка существования пользователя (финальная)
#############################################################################

if [ "$USER_ALREADY_EXISTS" = false ]; then
    log_info "Проверка существования пользователя..."
    USER_EXISTS=$(kubectl exec -i deployment/bastion -n bastion -- \
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname = '$USER_APP';" 2>/dev/null)

    if [ "$USER_EXISTS" != "1" ]; then
        log_error "Пользователь '$USER_APP' не найден в базе данных"
        log_error "Убедитесь, что пользователь создан через панель Selectel"
        exit 1
    fi
    log_success "Пользователь '$USER_APP' найден в базе данных"
    echo ""
fi

#############################################################################
# Проверка и создание схемы (ТЕПЕРЬ ШАГ 3!)
#############################################################################

log_step "Шаг 3/5: Проверка и создание схемы в PostgreSQL..."
echo ""

# Проверка существования схемы
SCHEMA_EXISTS=$(kubectl exec -i deployment/bastion -n bastion -- \
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -tAc \
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name = '$SCHEMA_NAME';" 2>/dev/null)

SCHEMA_ALREADY_EXISTS=false

if [ "$SCHEMA_EXISTS" = "$SCHEMA_NAME" ]; then
    SCHEMA_ALREADY_EXISTS=true
    log_warning "Схема '$SCHEMA_NAME' уже существует"
    echo ""
    read -p "Схема уже создана. Продолжить с выдачей прав и созданием Secret? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Операция отменена"
        exit 0
    fi
else
    # SQL скрипт для создания схемы
    # ВАЖНО: Теперь пользователь УЖЕ существует, можем сразу назначить его владельцем!
    SQL_CREATE_SCHEMA=$(cat <<EOF
CREATE SCHEMA IF NOT EXISTS ${SCHEMA_NAME};
COMMENT ON SCHEMA ${SCHEMA_NAME} IS 'Schema for ${SERVICE_NAME} service in ${ENVIRONMENT} environment';

-- КРИТИЧНО: Сменить владельца схемы на пользователя приложения (он уже существует!)
ALTER SCHEMA ${SCHEMA_NAME} OWNER TO ${USER_APP};
EOF
)

    kubectl exec -i deployment/bastion -n bastion -- \
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" <<< "$SQL_CREATE_SCHEMA" 2>&1 | grep -v "^psql" | grep -v "NOTICE"

    if [ $? -ne 0 ]; then
        log_error "Ошибка при создании схемы"
        exit 1
    fi

    log_success "Схема '$SCHEMA_NAME' создана и владелец назначен"
fi

echo ""

#############################################################################
# Выдача прав пользователю на схему
#############################################################################

log_step "Шаг 4/5: Выдача прав пользователю на схему..."
echo ""

# SQL скрипт для выдачи прав
SQL_GRANT_PRIVILEGES=$(cat <<EOF
-- ШАГ 1: КРИТИЧНО! Отозвать права у PUBLIC (это затрагивает ВСЕХ пользователей)
REVOKE ALL ON SCHEMA ${SCHEMA_NAME} FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA ${SCHEMA_NAME} FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ${SCHEMA_NAME} FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ${SCHEMA_NAME} FROM PUBLIC;

-- ШАГ 2: Выдача прав ТОЛЬКО своему пользователю
GRANT USAGE, CREATE ON SCHEMA ${SCHEMA_NAME} TO ${USER_APP};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA ${SCHEMA_NAME} TO ${USER_APP};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ${SCHEMA_NAME} TO ${USER_APP};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA ${SCHEMA_NAME} TO ${USER_APP};

-- ШАГ 3: Автоматические права на будущие объекты (FOR USER - критично!)
ALTER DEFAULT PRIVILEGES FOR USER ${USER_APP} IN SCHEMA ${SCHEMA_NAME} 
    GRANT ALL ON TABLES TO ${USER_APP};
ALTER DEFAULT PRIVILEGES FOR USER ${USER_APP} IN SCHEMA ${SCHEMA_NAME} 
    GRANT ALL ON SEQUENCES TO ${USER_APP};
ALTER DEFAULT PRIVILEGES FOR USER ${USER_APP} IN SCHEMA ${SCHEMA_NAME} 
    GRANT ALL ON FUNCTIONS TO ${USER_APP};

-- ШАГ 4: Запретить создание новых схем своему пользователю
REVOKE CREATE ON DATABASE ${PGDATABASE} FROM ${USER_APP};

-- ШАГ 5: Запретить доступ к схеме public своему пользователю
REVOKE ALL ON SCHEMA public FROM ${USER_APP};
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM ${USER_APP};
EOF
)

kubectl exec -i deployment/bastion -n bastion -- \
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" <<< "$SQL_GRANT_PRIVILEGES" 2>&1 | grep -v "^psql" | grep -v "NOTICE" | grep -v "WARNING"

if [ $? -ne 0 ]; then
    log_error "Ошибка при выдаче прав"
    exit 1
fi

log_success "Права на схему '$SCHEMA_NAME' выданы пользователю '$USER_APP'"
echo ""

#############################################################################
# Проверка подключения с новым пользователем
#############################################################################

if [ "$SKIP_USER_CREATION" = false ]; then
    log_info "Проверка подключения с пользователем..."
    TEST_CONNECTION=$(kubectl exec -i deployment/bastion -n bastion -- bash -c \
        "PGPASSWORD='$PASSWORD_APP' psql -h '$PGHOST' -p '$PGPORT' -U '$USER_APP' -d '$PGDATABASE' -tAc 'SELECT current_user;'" 2>&1)

    if [[ "$TEST_CONNECTION" == *"password authentication failed"* ]]; then
        log_error "Не удалось подключиться с введённым паролем"
        log_error "Проверьте правильность пароля в панели Selectel"
        exit 1
    fi

    if [ "$TEST_CONNECTION" = "$USER_APP" ]; then
        log_success "Подключение успешно (пользователь: $USER_APP)"
    else
        log_warning "Не удалось проверить подключение, но продолжаем..."
    fi
    echo ""
fi

#############################################################################
# Создание Kubernetes Secret
#############################################################################

if [ "$SKIP_USER_CREATION" = false ]; then
    log_step "Шаг 5/5: Создание Kubernetes Secret..."
    echo ""

    # Создание namespace если не существует
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

    # Проверка существования Secret
    if kubectl get secret "$SECRET_NAME" -n "$K8S_NAMESPACE" &>/dev/null; then
        log_warning "Secret '$SECRET_NAME' уже существует"
        if [ "$UPDATE_PASSWORD" = true ]; then
            log_info "Secret будет обновлён с новым паролем"
            kubectl delete secret "$SECRET_NAME" -n "$K8S_NAMESPACE" >/dev/null 2>&1
        else
            read -p "Обновить существующий Secret? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                kubectl delete secret "$SECRET_NAME" -n "$K8S_NAMESPACE" >/dev/null 2>&1
                log_info "Старый Secret удалён"
            else
                log_warning "Secret не обновлён. Завершение работы."
                exit 0
            fi
        fi
    fi

    # Создание нового Secret
    kubectl create secret generic "$SECRET_NAME" \
        --from-literal=host="$PGHOST" \
        --from-literal=port="${PGPORT:-5432}" \
        --from-literal=dbname="$PGDATABASE" \
        --from-literal=user="$USER_APP" \
        --from-literal=password="$PASSWORD_APP" \
        --from-literal=schema="$SCHEMA_NAME" \
        -n "$K8S_NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "Kubernetes Secret '$SECRET_NAME' создан в namespace '$K8S_NAMESPACE'"
    else
        log_error "Ошибка при создании Kubernetes Secret"
        exit 1
    fi
    echo ""
else
    log_step "Шаг 5/5: Создание Kubernetes Secret пропущено"
    echo ""
    log_info "Secret не обновляется, так как пароль не был изменён"
    echo ""
fi

#############################################################################
# Итоговая информация
#############################################################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Инфраструктура успешно создана!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Результат:"
echo ""
echo "  🗄️  PostgreSQL:"
if [ "$SCHEMA_ALREADY_EXISTS" = true ]; then
    echo -e "     Схема:        ${YELLOW}${SCHEMA_NAME}${NC} ${CYAN}(существовала)${NC}"
else
    echo -e "     Схема:        ${GREEN}${SCHEMA_NAME}${NC} ${CYAN}(создана)${NC}"
fi
if [ "$USER_ALREADY_EXISTS" = true ]; then
    echo -e "     Пользователь: ${YELLOW}${USER_APP}${NC} ${CYAN}(существовал)${NC}"
else
    echo -e "     Пользователь: ${GREEN}${USER_APP}${NC} ${CYAN}(создан)${NC}"
fi
echo -e "     Права:        ${GREEN}✅ CREATE объектов в своей схеме${NC}"
echo -e "                   ${GREEN}✅ Владелец схемы${NC}"
echo -e "                   ${GREEN}✅ Изоляция от других схем${NC}"
echo -e "                   ${RED}❌ CREATE новых схем запрещён${NC}"
echo -e "                   ${RED}❌ Доступ к схеме public запрещён${NC}"
echo ""

if [ "$SKIP_USER_CREATION" = false ]; then
    echo "  🔐 Kubernetes Secret:"
    echo -e "     Название:  ${GREEN}${SECRET_NAME}${NC}"
    echo -e "     Namespace: ${GREEN}${K8S_NAMESPACE}${NC}"
    if [ "$UPDATE_PASSWORD" = true ]; then
        echo -e "     Статус:    ${CYAN}Обновлён с новым паролем${NC}"
    fi
    echo ""
    echo "  ✅ Доступные ключи в Secret:"
    echo "     • host"
    echo "     • port"
    echo "     • dbname"
    echo "     • user"
    echo "     • password"
    echo "     • schema"
else
    echo "  🔐 Kubernetes Secret:"
    echo -e "     Статус: ${YELLOW}Не обновлялся${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📖 Следующие шаги:"
echo ""
echo "  1️⃣  Проверить права пользователя:"
echo -e "     ${CYAN}./test-schema-permissions.sh $SERVICE_NAME $ENVIRONMENT${NC}"
echo ""
echo "  2️⃣  Проверить созданный Secret:"
echo -e "     ${CYAN}kubectl get secret $SECRET_NAME -n $K8S_NAMESPACE${NC}"
echo ""
echo "  3️⃣  Просмотреть содержимое Secret:"
echo -e "     ${CYAN}kubectl get secret $SECRET_NAME -n $K8S_NAMESPACE -o yaml${NC}"
echo ""
echo "  4️⃣  Протестировать подключение:"
echo -e "     ${CYAN}kubectl exec -it deployment/bastion -n bastion -- bash${NC}"
echo -e "     ${CYAN}PGPASSWORD='***' psql -h $PGHOST -U $USER_APP -d $PGDATABASE${NC}"
echo -e "     ${CYAN}SET search_path TO '$SCHEMA_NAME';${NC}"
echo -e "     ${CYAN}SELECT current_schema();${NC}"
echo ""
echo "  5️⃣  Использовать в приложении:"
echo -e "     Укажите secretName: ${CYAN}$SECRET_NAME${NC} в Deployment вашего сервиса"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
