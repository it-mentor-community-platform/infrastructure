### Инструкция по созданию и настройке PostgreSQL кластера в Selectel

---

#### Общая информация

**Цель:** Создать минимальный PostgreSQL кластер для двух окружений (stage и prod) с корректной UTF-8 кодировкой и разделением доступа.

**Стоимость конфигурации:**
- 2 vCPU Flex: **1 862,96 ₽/месяц**
- 8 ГБ RAM Flex: **2 488 ₽/месяц**
- 64 ГБ Локальный диск Flex: **1 415,15 ₽/месяц**

**Итого: 5 766,1 ₽/месяц** (около 69 193 ₽/год)

---

#### Шаг 1: Создание PostgreSQL кластера через GUI Selectel

##### 1.1. Войдите в панель Selectel

1. Перейдите в **Cloud Platform** → **Managed Databases**
2. Нажмите **Создать кластер**

##### 1.2. Выберите параметры кластера

**Базовые настройки:**
- **Тип СУБД:** PostgreSQL
- **Версия:** 17.x (последняя стабильная)
- **Имя кластера:** `postgres-cluster-prod` (или любое удобное)

**Конфигурация узлов:**
- **CPU:** 2 vCPU Flex
- **RAM:** 8 ГБ Flex
- **Диск:** 64 ГБ Локальный диск Flex
- **Количество узлов:** 1 (для минимальной конфигурации)

**Сеть:**
- **Регион:** ru-1 (Москва) или ru-3 (Санкт-Петербург)
- **Приватная сеть:** Выберите существующую или создайте новую
- **Публичный IP:** Отключите (безопаснее)

##### 1.3. Настройки БД и кодировки

**⚠️ ВАЖНО: Настройки кодировки задаются при создании базы данных!**

При создании кластера Selectel автоматически создаёт базу `postgres` с кодировкой UTF-8. 

После создания кластера нужно будет создать рабочую базу данных `db_main` с правильными параметрами:

```sql
CREATE DATABASE db_main
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;
```

##### 1.4. Учётные данные

- **Имя администратора:** `admin` (или задайте своё)
- **Пароль:** Selectel сгенерирует автоматически. **Обязательно сохраните его в безопасном месте!**

**Рекомендация:** Используйте менеджер паролей (1Password, Bitwarden) или Kubernetes Secret.

##### 1.5. Создание кластера

1. Нажмите **Создать кластер**
2. Дождитесь завершения создания (5-10 минут)
3. После создания вы получите:
   - Адрес подключения: `master.<UUID>.c.dbaas.selcloud.ru`
   - Порт: `5432`
   - Логин администратора: `admin`
   - Пароль администратора

---

#### Шаг 2: Сохранение рутовых кредов в Kubernetes Secret

##### 2.1. Создайте namespace для бастиона (если не создан)

```bash
kubectl create namespace bastion
```

##### 2.2. Скачайте SSL/TLS сертификат

1. В панели Selectel откройте ваш PostgreSQL кластер
2. Найдите раздел **Подключение** или **Connection**
3. Скачайте **CA-сертификат** (root.crt)
4. Сохраните файл локально

##### 2.3. Подготовьте файлы с кредами

**Сохраните пароль во временный файл:**

```bash
echo -n 'ВАШ_ПАРОЛЬ_ОТ_SELECTEL' > /tmp/pg_password
chmod 600 /tmp/pg_password
```

**Сохраните CA-сертификат в ConfigMap:**

```bash
kubectl create configmap postgres-ca-cert \
  --from-file=root.crt=/path/to/downloaded/root.crt \
  -n bastion
```

##### 2.4. Создайте Secret с кредами администратора

> **Примечание:** Бастион — это pod в Kubernetes для безопасного доступа к базе данных. Его конфигурация должна находиться в репозитории `infrastructure/bastion`.

```bash
kubectl create secret generic postgres-creds \
  --from-literal=host=master.<UUID>.c.dbaas.selcloud.ru \
  --from-literal=port=5432 \
  --from-literal=dbname=postgres \
  --from-literal=user=admin \
  --from-file=password=/tmp/pg_password \
  -n bastion
```

**⚠️ Важно:** Замените `<UUID>` на реальный UUID вашего кластера из панели Selectel.

##### 2.5. Удалите временный файл

```bash
rm /tmp/pg_password
```

##### 2.6. Проверьте созданный Secret

```bash
kubectl get secret postgres-creds -n bastion -o yaml
```

---

#### Шаг 3: Подключение к кластеру через бастион

##### 3.1. Разверните бастион pod (если не развёрнут)

> **Примечание:** Полная конфигурация бастиона должна находиться в репозитории `infrastructure/bastion`.

Создайте файл `bastion-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bastion
  namespace: bastion
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bastion
  template:
    metadata:
      labels:
        app: bastion
    spec:
      containers:
      - name: bastion
        image: postgres:17-alpine
        command: ["/bin/sh"]
        args: 
          - "-c"
          - |
            apk add --no-cache curl wget openssh-client bash vim bind-tools

            mkdir -p /root/.postgresql
            if [ -f /postgres-ca/root.crt ]; then
              cp /postgres-ca/root.crt /root/.postgresql/
              chmod 0600 /root/.postgresql/root.crt
            fi

            echo "$PGHOST:$PGPORT:$PGDATABASE:$PGUSER:$PGPASSWORD" > /root/.pgpass
            chmod 0600 /root/.pgpass

            echo "Bastion ready! PostgreSQL client version:"
            psql --version

            while true; do sleep 3600; done
        env:
        - name: PGHOST
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: host
        - name: PGPORT
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: port
        - name: PGDATABASE
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: dbname
        - name: PGUSER
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: user
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-creds
              key: password
        - name: PGSSLMODE
          value: "verify-ca"
        - name: PGSSLROOTCERT
          value: "/root/.postgresql/root.crt"
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "100m"
        volumeMounts:
        - name: postgres-ca
          mountPath: /postgres-ca
          readOnly: true
      volumes:
      - name: postgres-ca
        configMap:
          name: postgres-ca-cert
          defaultMode: 0600
```

**Примените манифест:**

```bash
kubectl apply -f bastion-deployment.yaml
```

**Дождитесь запуска pod:**

```bash
kubectl get pods -n bastion -w
```

##### 3.2. Подключитесь к бастиону

```bash
kubectl exec -it deployment/bastion -n bastion -- bash
```

##### 3.3. Подключитесь к PostgreSQL

Благодаря переменным окружения, достаточно выполнить:

```bash
psql
```

Вы должны увидеть:

```
psql (17.x, server 17.x)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

---

#### Шаг 4: Создание рабочей базы данных с UTF-8

##### 4.1. Создайте базу данных db_main

```sql
CREATE DATABASE db_main
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0
    OWNER = admin;
```

##### 4.2. Подключитесь к новой базе

```sql
\c db_main
```

##### 4.3. Проверьте настройки кодировки

```sql
-- Проверка кодировки базы
\l+ db_main

-- Проверка параметров сервера
SHOW server_encoding;
SHOW client_encoding;
```

**Ожидаемый результат:**

```
 server_encoding 
-----------------
 UTF8
(1 row)

 client_encoding 
-----------------
 UTF8
(1 row)
```

---

#### Шаг 5: Тестирование UTF-8 кодировки

##### 5.1. Создайте тестовую таблицу

```sql
CREATE TABLE utf8_test (
    id SERIAL PRIMARY KEY,
    text_field TEXT,
    emoji_field TEXT
);
```

##### 5.2. Вставьте мультиязычные данные

```sql
INSERT INTO utf8_test (text_field, emoji_field) VALUES 
    ('Hello мир 你好', '🚀🎉'),
    ('Тестовая строка с ёлкой', '🌲'),
    ('Special: café, naïve, Zürich', '☕'),
    ('Эмодзи: 🔥💻🎵', '👍');
```

##### 5.3. Проверьте корректность сохранения

```sql
SELECT * FROM utf8_test;
```

**Ожидаемый результат:**

```
 id |          text_field          | emoji_field 
----+------------------------------+-------------
  1 | Hello мир 你好               | 🚀🎉
  2 | Тестовая строка с ёлкой      | 🌲
  3 | Special: café, naïve, Zürich | ☕
  4 | Эмодзи: 🔥💻🎵               | 👍
(4 rows)
```

##### 5.4. Проверьте подсчёт символов

```sql
SELECT 
    text_field,
    length(text_field) as char_count,
    octet_length(text_field) as byte_count
FROM utf8_test;
```

**Корректный результат:**

```
          text_field          | char_count | byte_count 
------------------------------+------------+------------
 Hello мир 你好               |         12 |         19
 Тестовая строка с ёлкой      |         23 |         43
 Special: café, naïve, Zürich |         28 |         31
 Эмодзи: 🔥💻🎵               |         11 |         26
(4 rows)
```

**✅ Если `char_count` и `byte_count` различаются — UTF-8 работает корректно!**

##### 5.5. Проверьте сортировку

```sql
SELECT text_field FROM utf8_test ORDER BY text_field;
```

##### 5.6. Очистите тестовые данные

```sql
DROP TABLE utf8_test;
```

**🎉 Если все тесты прошли успешно — UTF-8 настроен правильно!**
