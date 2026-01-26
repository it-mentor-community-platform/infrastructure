### Инструкция: Развертывание postgres-client Pod для доступа разработчиков

#### Описание

Этот документ описывает процесс развертывания `postgres-client` Pod в Kubernetes для обеспечения безопасного доступа разработчиков к PostgreSQL базе данных через `kubectl port-forward`.

**Архитектура решения:**
```
Разработчик → kubectl port-forward → postgres-client Pod → PostgreSQL Selectel
```

**Преимущества:**
- ✅ Безопасный доступ через Kubernetes RBAC
- ✅ Не требует открытия внешних портов PostgreSQL
- ✅ Централизованное управление доступом
- ✅ Аудит всех подключений через Kubernetes API

---

### Предварительные требования

- Kubernetes кластер (версия 1.24+)
- kubectl с правами администратора кластера
- PostgreSQL база данных (Selectel Managed Database)
- Существующий namespace `postgres`
- Secret с данными подключения к PostgreSQL
- ConfigMap с CA сертификатом PostgreSQL

---

### Структура проекта

```
infrastructure/
└── postgres/
    └── postgres-client/
        ├── 01-developer-guide.md
        ├── 01-postgres-client-deployment.yaml
        ├── 02-postgres-client-deployment.md
        └── 02-postgres-client-service.yaml
```

---

### Шаг 1: Подготовка Secrets и ConfigMaps

##### Создать Secret с учетными данными PostgreSQL

**Файл: `postgres-creds-secret.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-creds
  namespace: postgres
type: Opaque
stringData:
  host: "your-postgres-host.example.com"
  port: "5432"
  dbname: "db_main"
  user: "admin"
  password: "your-secure-password"
```

**Применить:**
```bash
kubectl apply -f postgres-creds-secret.yaml
```

##### Создать ConfigMap с CA сертификатом

**Получить CA сертификат из Selectel:**
1. Панель управления Selectel → Managed Databases
2. Ваша PostgreSQL база → Настройки → SSL
3. Скачать CA сертификат (`root.crt`)

**Файл: `postgres-client-config.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-client-config
  namespace: postgres
data:
  root.crt: |
    -----BEGIN CERTIFICATE-----
    <содержимое вашего CA сертификата>
    -----END CERTIFICATE-----
```

**Применить:**
```bash
kubectl apply -f postgres-client-config.yaml
```

---

### Шаг 2: Развертывание postgres-client

##### Deployment манифест

**Файл: `01-postgres-client-deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-client
  namespace: postgres
  labels:
    app: postgres-client
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-client
  template:
    metadata:
      labels:
        app: postgres-client
    spec:
      containers:
      - name: postgres-client
        image: alpine/socat:latest
        command:
          - sh
          - -c
          - |
            echo "Starting PostgreSQL proxy..."
            echo "Forwarding localhost:5432 -> $PGHOST:$PGPORT"
            socat TCP-LISTEN:5432,fork,reuseaddr TCP:$PGHOST:$PGPORT

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

        ports:
        - containerPort: 5432
          protocol: TCP

        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "200m"

        readinessProbe:
          tcpSocket:
            port: 5432
          initialDelaySeconds: 5
          periodSeconds: 10

        livenessProbe:
          tcpSocket:
            port: 5432
          initialDelaySeconds: 10
          periodSeconds: 30
```

**Что делает этот Pod:**
- Запускает `socat` для проброса TCP соединений
- Слушает порт 5432 внутри Pod
- Пробрасывает все подключения к PostgreSQL (`$PGHOST:$PGPORT`)
- Использует credentials из Secret

**Применить:**
```bash
kubectl apply -f 01-postgres-client-deployment.yaml
```

##### Service манифест

**Файл: `02-postgres-client-service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-client
  namespace: postgres
  labels:
    app: postgres-client
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
    protocol: TCP
    name: postgresql
  selector:
    app: postgres-client
```

**Применить:**
```bash
kubectl apply -f 02-postgres-client-service.yaml
```

---

### Шаг 3: Проверка развертывания

##### Проверить статус Pod

```bash
# Проверить что Pod запустился
kubectl get pods -n postgres

# Ожидаемый вывод:
# NAME                               READY   STATUS    RESTARTS   AGE
# postgres-client-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

##### Проверить логи

```bash
# Посмотреть логи Pod
kubectl logs -n postgres deployment/postgres-client

# Ожидаемый вывод:
# Starting PostgreSQL proxy...
# Forwarding localhost:5432 -> your-postgres-host.example.com:5432
```

##### Проверить Service

```bash
# Проверить Service
kubectl get svc -n postgres

# Ожидаемый вывод:
# NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# postgres-client   ClusterIP   10.x.x.x        <none>        5432/TCP   1m
```

##### Тестовое подключение

```bash
# Создать port-forward
kubectl port-forward -n postgres svc/postgres-client 5432:5432

# В другом терминале - проверить подключение
psql -h localhost -p 5432 -U admin -d db_main

# Если всё работает - увидите приглашение psql
```

---

### Шаг 4: Обновление конфигурации

##### Обновить пароль PostgreSQL

```bash
# Обновить Secret
kubectl create secret generic postgres-creds \
  --from-literal=host=your-postgres-host.example.com \
  --from-literal=port=5432 \
  --from-literal=dbname=db_main \
  --from-literal=user=admin \
  --from-literal=password=new-secure-password \
  --namespace=postgres \
  --dry-run=client -o yaml | kubectl apply -f -

# Перезапустить Pod для применения изменений
kubectl rollout restart deployment/postgres-client -n postgres
```

##### Изменить версию образа

```bash
# Отредактировать Deployment
kubectl edit deployment postgres-client -n postgres

# Или через файл
kubectl apply -f 01-postgres-client-deployment.yaml
```

---

### Безопасность

##### RBAC

Минимальные права для разработчиков настроены в `infrastructure/developer-service-account/`:
- Только `get`, `list`, `portforward` на pods
- Запрет на `delete`, `update`, `patch`
- Доступ только к namespace `postgres`

Подробнее см. документацию: `infrastructure/developer-service-account/03-serviceaccount-kubeconfig-guide.md`
