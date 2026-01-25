### Конвенция создания схем и пользователей PostgreSQL

---

#### Общие принципы

Эта инструкция описывает соглашение о наименовании и создании схем, пользователей и секретов для PostgreSQL кластера. Используйте её как справочник при добавлении новых сервисов.

---

#### Соглашение о наименовании

##### Схемы

Формат: `<service_name>_<environment>`

**Примеры:**
- `auth-prod` — схема для сервиса аутентификации в production
- `auth-staging` — схема для сервиса аутентификации в staging
- `orders-prod` — схема для сервиса заказов в production
- `orders-staging` — схема для сервиса заказов в staging

##### Пользователи

**Для приложений (полный доступ):**  
Формат: `<service_name>_<environment>_app`

**Примеры:**
- `auth_prod_app`
- `auth_staging_app`
- `orders_prod_app`

**Для чтения (read-only):**  
Формат: `<service_name>_<environment>_readonly`

**Примеры:**
- `auth_prod_readonly`
- `auth_staging_readonly`
- `orders_prod_readonly`

##### Kubernetes Secrets

Формат: `postgres-<service_name>-<environment>-<access_type>`

**Примеры:**
- `postgres-auth-prod-app`
- `postgres-auth-staging-app`
- `postgres-auth-prod-readonly`
- `postgres-orders-staging-app`

---

#### Пример: Создание инфраструктуры для сервиса "auth"

##### 1. Создайте схемы

Подключитесь к базе данных через бастион:

```bash
kubectl exec -it deployment/bastion -n bastion -- psql
```

Создайте схемы для обоих окружений:

```sql
-- Схема для production
CREATE SCHEMA IF NOT EXISTS "auth-prod";

-- Схема для staging
CREATE SCHEMA IF NOT EXISTS "auth-staging";

-- Проверка
\dn
```

##### 2. Создайте пользователя для production (полный доступ)

```sql
-- Создание пользователя
CREATE USER auth_prod_app WITH PASSWORD 'СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_1';

-- Права на подключение к базе
GRANT CONNECT ON DATABASE db_main TO auth_prod_app;

-- Права на схему
GRANT USAGE, CREATE ON SCHEMA "auth-prod" TO auth_prod_app;

-- Права на все объекты
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "auth-prod" TO auth_prod_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA "auth-prod" TO auth_prod_app;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA "auth-prod" TO auth_prod_app;

-- Автоматические права на будущие объекты
ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-prod" 
GRANT ALL ON TABLES TO auth_prod_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-prod" 
GRANT ALL ON SEQUENCES TO auth_prod_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-prod" 
GRANT ALL ON FUNCTIONS TO auth_prod_app;
```

##### 3. Создайте пользователя для production (read-only)

```sql
-- Создание пользователя
CREATE USER auth_prod_readonly WITH PASSWORD 'СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_2';

-- Права на подключение
GRANT CONNECT ON DATABASE db_main TO auth_prod_readonly;

-- Права на схему (только чтение)
GRANT USAGE ON SCHEMA "auth-prod" TO auth_prod_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA "auth-prod" TO auth_prod_readonly;

-- Автоматические права на будущие таблицы
ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-prod" 
GRANT SELECT ON TABLES TO auth_prod_readonly;
```

##### 4. Создайте пользователя для staging (полный доступ)

```sql
-- Создание пользователя
CREATE USER auth_staging_app WITH PASSWORD 'СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_3';

-- Права на подключение
GRANT CONNECT ON DATABASE db_main TO auth_staging_app;

-- Права на схему
GRANT USAGE, CREATE ON SCHEMA "auth-staging" TO auth_staging_app;

-- Права на все объекты
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA "auth-staging" TO auth_staging_app;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA "auth-staging" TO auth_staging_app;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA "auth-staging" TO auth_staging_app;

-- Автоматические права
ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-staging" 
GRANT ALL ON TABLES TO auth_staging_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-staging" 
GRANT ALL ON SEQUENCES TO auth_staging_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-staging" 
GRANT ALL ON FUNCTIONS TO auth_staging_app;
```

##### 5. Создайте пользователя для staging (read-only)

```sql
-- Создание пользователя
CREATE USER auth_staging_readonly WITH PASSWORD 'СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_4';

-- Права на подключение
GRANT CONNECT ON DATABASE db_main TO auth_staging_readonly;

-- Права на схему (только чтение)
GRANT USAGE ON SCHEMA "auth-staging" TO auth_staging_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA "auth-staging" TO auth_staging_readonly;

-- Автоматические права
ALTER DEFAULT PRIVILEGES IN SCHEMA "auth-staging" 
GRANT SELECT ON TABLES TO auth_staging_readonly;
```

##### 6. Проверьте созданных пользователей

```sql
\du
```

##### 7. Создайте Kubernetes Secret для production (app)

```bash
kubectl create secret generic postgres-auth-prod-app \
  --from-literal=host=master.<UUID>.c.dbaas.selcloud.ru \
  --from-literal=port=5432 \
  --from-literal=dbname=db_main \
  --from-literal=user=auth_prod_app \
  --from-literal=password='СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_1' \
  --from-literal=schema=auth-prod \
  -n auth-service
```

##### 8. Создайте Kubernetes Secret для production (readonly)

```bash
kubectl create secret generic postgres-auth-prod-readonly \
  --from-literal=host=master.<UUID>.c.dbaas.selcloud.ru \
  --from-literal=port=5432 \
  --from-literal=dbname=db_main \
  --from-literal=user=auth_prod_readonly \
  --from-literal=password='СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_2' \
  --from-literal=schema=auth-prod \
  -n auth-service
```

##### 9. Создайте Kubernetes Secret для staging (app)

```bash
kubectl create secret generic postgres-auth-staging-app \
  --from-literal=host=master.<UUID>.c.dbaas.selcloud.ru \
  --from-literal=port=5432 \
  --from-literal=dbname=db_main \
  --from-literal=user=auth_staging_app \
  --from-literal=password='СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_3' \
  --from-literal=schema=auth-staging \
  -n auth-service
```

##### 10. Создайте Kubernetes Secret для staging (readonly)

```bash
kubectl create secret generic postgres-auth-staging-readonly \
  --from-literal=host=master.<UUID>.c.dbaas.selcloud.ru \
  --from-literal=port=5432 \
  --from-literal=dbname=db_main \
  --from-literal=user=auth_staging_readonly \
  --from-literal=password='СГЕНЕРИРОВАННЫЙ_ПАРОЛЬ_4' \
  --from-literal=schema=auth-staging \
  -n auth-service
```

**⚠️ Важно:**
- Замените `<UUID>` на реальный UUID вашего кластера
- Замените `auth-service` на namespace вашего приложения
- Используйте сильные пароли (можно сгенерировать через `openssl rand -base64 32`)

##### 11. Проверьте созданные Secrets

```bash
kubectl get secrets -n auth-service | grep postgres
```

---

#### Быстрая справка по командам

##### Генерация пароля

```bash
openssl rand -base64 32
```

Или в psql:

```sql
SELECT encode(gen_random_bytes(24), 'base64') as password;
```

##### Проверка схем

```sql
\dn
```

##### Проверка пользователей

```sql
\du
```

##### Проверка прав доступа к схеме

```sql
\dn+ "auth-prod"
```

##### Тестирование подключения

```bash
# Из бастиона
kubectl exec -it deployment/bastion -n bastion -- bash

# Подключение от имени пользователя
PGPASSWORD='пароль' psql \
  -h master.<UUID>.c.dbaas.selcloud.ru \
  -U auth_prod_app \
  -d db_main \
  -c "SET search_path TO 'auth-prod'; SELECT current_schema();"
```

---

#### Итоговая структура для сервиса "auth"

```
db_main (база данных)
│
├── Схема: auth-prod
│   ├── Пользователи:
│   │   ├── auth_prod_app (полный доступ)
│   │   └── auth_prod_readonly (только чтение)
│   └── Таблицы: (создаются приложением)
│
└── Схема: auth-staging
    ├── Пользователи:
    │   ├── auth_staging_app (полный доступ)
    │   └── auth_staging_readonly (только чтение)
    └── Таблицы: (создаются приложением)
```

```
Kubernetes Secrets (namespace: auth-service)
├── postgres-auth-prod-app
├── postgres-auth-prod-readonly
├── postgres-auth-staging-app
└── postgres-auth-staging-readonly
```

---

#### Использование в приложении

##### Пример Deployment с кредами

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: auth-service
spec:
  template:
    spec:
      containers:
      - name: app
        image: auth-service:latest
        env:
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: postgres-auth-prod-app
              key: host
        - name: DB_PORT
          valueFrom:
            secretKeyRef:
              name: postgres-auth-prod-app
              key: port
        - name: DB_NAME
          valueFrom:
            secretKeyRef:
              name: postgres-auth-prod-app
              key: dbname
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-auth-prod-app
              key: user
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-auth-prod-app
              key: password
        - name: DB_SCHEMA
          valueFrom:
            secretKeyRef:
              name: postgres-auth-prod-app
              key: schema
        - name: DB_SSLMODE
          value: "verify-ca"
        volumeMounts:
        - name: postgres-ca
          mountPath: /app/certs
          readOnly: true
      volumes:
      - name: postgres-ca
        configMap:
          name: postgres-ca-cert
```