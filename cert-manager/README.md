  ### Установка и настройка TLS сертификатов с cert-manager

  В данной инструкции мы будем настраивать автоматическое управление TLS/SSL сертификатами
  в Kubernetes кластере с использованием cert-manager и Let's Encrypt.

  **Используемые компоненты:**
  - **cert-manager** - автоматическое управление сертификатами
  - **Let's Encrypt** - бесплатный центр сертификации
  - **ClusterIssuer** - глобальная конфигурация для выпуска сертификатов
  - **HTTP-01 challenge** - метод подтверждения владения доменом

  #### Структура репозитория

  infrastructure/cert-manager/

  ├── README.md - инструкция

  ├── values.yaml - Helm values для cert-manager

  ├── letsencrypt-prod.yaml - Production ClusterIssuer

  ├── letsencrypt-staging.yaml - Staging ClusterIssuer для тестов

  ├── test-resources/

  │ ├── nginx-ingress.yaml - Тестовый Ingress для nginx

  │ └── tomcat-ingress.yaml - Тестовый Ingress для tomcat

  └── examples/

  └── ingress-with-tls-template.yaml - Шаблон Ingress с TLS (пример ингресса для новых проектов)

  #### Шаг 1: Установка cert-manager
  ##### 1.1. Добавление Helm репозитория
  ```bash
  helm repo add jetstack https://charts.jetstack.io  
  helm repo update
  ```
  
  ##### 1.2. Установка CRDs (Custom Resource Definitions)
  CRDs должны быть установлены до установки Helm чарта:
  ```bash
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.2/cert-manager.crds.yaml
  ```
  *Примечание: CRD (Custom Resource Definition) добавляют в Kubernetes новые типы ресурсов: Certificate, Issuer, ClusterIssuer, CertificateRequest. Без них cert-manager не сможет работать.*
  ##### 1.3. Установка cert-manager через Helm
  Находяся в одной директории с values (см. Структура репозитория):
  ```
  helm install cert-manager jetstack/cert-manager \
  --version v1.19.2 \
  --namespace cert-manager \
  --create-namespace \
  --values values.yaml
  ```
  ##### 1.5. Проверка установки
  Проверяем, что все поды запустились.
  ```bash
kubectl get pods -n cert-manager

# Ожидаемый вывод - 3 пода в статусе Running:
# NAME                                      READY   STATUS    RESTARTS   AGE
# cert-manager-<hash>                       1/1     Running   0          1m
# cert-manager-cainjector-<hash>            1/1     Running   0          1m
# cert-manager-webhook-<hash>               1/1     Running   0          1m
```
Проверяем CRDs.
```bash
kubectl get crd | grep cert-manager

# Должны быть:
# certificates.cert-manager.io
# certificaterequests.cert-manager.io
# challenges.acme.cert-manager.io
# clusterissuers.cert-manager.io
# issuers.cert-manager.io
# orders.acme.cert-manager.io
```
#### Шаг 2: Создание ClusterIssuer
ClusterIssuer - это глобальная конфигурация, которая сообщает cert-manager, как и где получать сертификаты. Он работает на уровне всего кластера и может выпускать сертификаты для любого namespace.
В репозитории есть 2 файла:
- letsencrypt-prod.yaml
- letsencrypt-staging.yaml

Staging используется для тестирования конфигурации без риска упереться в лимиты Let's Encrypt (5 сертификатов/домен в неделю). Staging сертификаты не доверяются браузерами - это нормально.
##### 2.1. Применение конфигурации

Не забудьте изменить email на реальный!
```bash
kubectl apply -f letsencrypt-prod.yaml
kubectl apply -f letsencrypt-staging.yaml
```
##### 2.2. Проверка статуса ClusterIssuer
```bash
➜  ~ kubectl get clusterissuer
NAME                  READY   AGE
letsencrypt-prod      True    34h
letsencrypt-staging   True    34h
➜  ~ kubectl describe clusterissuer letsencrypt-prod
➜  ~ kubectl describe clusterissuer letsencrypt-staging
```
Статус должен быть Ready: True. Если нет - проверьте логи.
#### Шаг 3: Настройка тестовых Ingress ресурсов
##### 3.1. Применение Ingress
Применяем обновленный ингресс с сертификатами в наши тестовые ресурсы ```test-nginx``` и ```tomcat-test```.
Файлы с обновленным ингрессом ищем в папке ```test-resources``` (см. структура репозитория).
```bash
kubectl apply -f test-resources/nginx-ingress.yaml
kubectl apply -f test-resources/tomcat-ingress.yaml
```
##### 3.2. Автоматическое создание Certificate
После применения Ingress cert-manager автоматически:

- Обнаружит аннотацию cert-manager.io/cluster-issuer

- Создаст ресурс Certificate в соответствующем namespace

- Запросит сертификат у Let's Encrypt через HTTP-01 challenge

- Сохранит сертификат в указанный Secret

- Ingress-контроллер начнёт использовать сертификат для HTTPS

Весь процесс занимает 1-3 минуты.
#### Шаг 4: Валидация работоспособности
##### 4.1. Проверка Certificate ресурсов
```bash
➜  ~ kubectl get certificate -n nginx-test
NAME             READY   SECRET           AGE
nginx-test-tls   True    nginx-test-tls   33h

➜  ~ kubectl get certificate -n tomcat-test
NAME              READY   SECRET            AGE
tomcat-test-tls   True    tomcat-test-tls   33h
```
READY: True означает, что сертификат успешно получен и готов к использованию.

```bash
# Детали для nginx (staging)
kubectl describe certificate nginx-test-tls -n nginx-test

# Детали для tomcat (production)
kubectl describe certificate tomcat-test-tls -n tomcat-test

# В выводе проверяем:
# Status.Conditions.Ready: True
# Status.Not After: дата истечения (через 90 дней)
# Status.Renewal Time: дата автообновления (за 30 дней до истечения)
# Events: должны быть "Certificate issued successfully"
```
##### 4.2. Проверка Secret с сертификатами
Проверяем, что Secret'ы созданы:
```bash
kubectl get secret nginx-test-tls -n nginx-test
kubectl get secret tomcat-test-tls -n tomcat-test
```
Тип должен быть: kubernetes.io/tls
DATA должно быть: 2 (tls.crt и tls.key)
##### 4.3. Проверка через OpenSSL
```bash
# Проверка tomcat (production сертификат)
openssl s_client -connect tomcat-test.staging.platform.zhukovsd.it:443 \
  -servername tomcat-test.staging.platform.zhukovsd.it
```
Ожидаемый результат для production:
```bash
depth=2 C = US, O = Internet Security Research Group, CN = ISRG Root X1
depth=1 C = US, O = Let's Encrypt, CN = R12
depth=0 CN = tomcat-test.staging.platform.zhukovsd.it
Verification: OK
Verify return code: 0 (ok)
```
```bash
# Проверка nginx (staging сертификат)
openssl s_client -connect nginx-test.staging.platform.zhukovsd.it:443 \
  -servername nginx-test.staging.platform.zhukovsd.it
```
Ожидаемый результат для staging:
```bash
depth=2 C = US, O = (STAGING) Internet Security Research Group, CN = (STAGING) Pretend Pear X1
...
Verify return code: 18 (self-signed certificate)
```
Для staging ошибка верификации - это нормально, staging сертификаты не доверяются.
##### 4.5. Проверка через браузер
Откройте в браузере
- https://tomcat-test.staging.platform.zhukovsd.it
- https://nginx-test.staging.platform.zhukovsd.it
#### Переключение со Staging на Production
Если вы сначала тестировали со staging, а теперь хотите production сертификат:
```bash
# 1. Удалите старый Secret со staging сертификатом
kubectl delete secret nginx-test-tls -n nginx-test

# 2. Измените аннотацию в Ingress на production
# В файле nginx-ingress.yaml:
# cert-manager.io/cluster-issuer: "letsencrypt-prod"

# 3. Примените изменённый манифест
kubectl apply -f test-resources/nginx-ingress.yaml

# 4. Проверьте получение нового сертификата (1-3 минуты)
kubectl get certificate -n nginx-test
kubectl describe certificate nginx-test-tls -n nginx-test
```

#### Сроки обновление сертификатов.
Cert-manager полностью автоматизирует обновление сертификатов:

- Сертификаты Let's Encrypt действуют 90 дней
- cert-manager начинает обновление за 30 дней до истечения
- Обновление происходит без простоя и без вашего участия
- После обновления новый сертификат сразу используется Ingress