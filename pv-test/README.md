### Работа с persistent томами в Selectel

В данной инструкции разбирается создание и использование persistent томов в Kubernetes кластере Selectel, а также демонстрация поведения политик `Retain` и `Delete` при работе с дисками.

**Используемые компоненты:**
- **Selectel Managed Kubernetes** – кластер в зоне ru-7
- **CSI драйвер Cinder** – драйвер для работы с дисками Selectel
- **StorageClass** – шаблон для автоматического создания PV
- **PersistentVolume (PV)** – представление диска в Kubernetes
- **PersistentVolumeClaim (PVC)** – запрос на выделение диска
- **HDD диски (basic.ru-7)** – самые дешёвые диски в Selectel

#### Структура репозитория

`infrastructure/pv-test/`

- `README.md` – инструкция
- `namespace.yaml` – namespace для тестового стенда
- `storageclass-retain.yaml` – StorageClass с политикой `Retain`
- `storageclass-delete.yaml` – StorageClass с политикой `Delete`
- `pvc-persistent.yaml` – PVC для постоянного тома (Retain)
- `pvc-temporary.yaml` – PVC для временного тома (Delete)
- `configmap.yaml` – конфиг nginx и простая HTML-страница
- `job-init.yaml` – единоразовая инициализация данных на томах
- `deployment.yaml` – деплоймент тестового сервиса
- `service.yaml` – ClusterIP service для приложения
- `ingress.yaml` – публикация сервиса наружу через HTTPS

#### Логика работы

```
Job (один раз):
├─ Создаёт файл test.txt с содержимым "TEST_DATA_SELECTEL_PV_2026"
├─ Вычисляет MD5 хеш файла
└─ Сохраняет хеш в checksum.txt

Init Container (при каждом запуске Pod):
├─ Проверяет наличие test.txt
├─ Проверяет наличие checksum.txt
├─ Вычисляет MD5 хеш файла
├─ Сравнивает с сохранённым хешем
└─ Записывает результат в result.txt:
   ├─ "OK: <hash>" - если всё в порядке
   ├─ "ERROR: File not found" - если диск был удалён
   └─ "ERROR: Checksum mismatch" - если данные повреждены

Nginx:
└─ Отображает содержимое result.txt через веб-интерфейс
```
### Предварительные требования

- Kubernetes кластер Selectel в зоне **ru-7**
- CSI драйвер Cinder (устанавливается автоматически при создании кластера)
- nginx-ingress-controller
- cert-manager с настроенным ClusterIssuer

#### Шаг 1: Проверка готовности кластера

Проверяем, что в кластере есть CSI драйвер и StorageClass.

```bash
kubectl get pods -n kube-system | grep csi

# Должны быть поды:
# csi-cinder-controllerplugin-...
# csi-cinder-nodeplugin-...

kubectl get storageclass
# Будет примерно такой вывод:
NAME                  PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
fast.ru-7a            cinder.csi.openstack.org   Delete          Immediate           true                   6d23h
```

#### Шаг 2: Базовая инфраструктура

Применяем базовые манифесты.

```bash
kubectl apply -f namespace.yaml
kubectl apply -f storageclass-retain.yaml
kubectl apply -f storageclass-delete.yaml
kubectl apply -f pvc-persistent.yaml
kubectl apply -f pvc-temporary.yaml
```

Проверяем создание PVC и PV.

```bash
kubectl get pvc -n pv-test

# Ожидаемый вывод (после биндинга):
# NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
# pv-test-persistent   Bound    pvc-...                                    1Gi        RWO            selectel-hdd-retain
# pv-test-temporary    Bound    pvc-2ace5262-0f9a-4001-9225-39ab0a38836e   1Gi        RWO            selectel-hdd-delete

kubectl get pv | grep pv-test

# Проверяем политику
kubectl get pv -o custom-columns=NAME:.metadata.name,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase | grep pv-test
# Должно быть:
# pvc-...   Retain   Bound
# pvc-...   Delete   Bound
```

#### Шаг 3: Конфигурация nginx и фронта

Применяем ConfigMap с конфигурацией nginx и HTML.

```bash
kubectl apply -f configmap.yaml
```

HTML-страница показывает результат проверки томов:

- `Persistent Volume (Retain)` – проверка файла и контрольной суммы на томе с политикой `Retain`
- `Temporary Volume (Delete)` – то же самое на томе с политикой `Delete`

#### Шаг 4: Инициализация данных (один раз)

Job создаёт одинаковый тестовый файл и контрольную сумму на обоих томах.

```bash
kubectl apply -f job-init.yaml

kubectl wait --for=condition=complete job/pv-init-once -n pv-test --timeout=60s

kubectl logs job/pv-init-once -n pv-test

# Ожидаемый вывод:
# === Initializing test data ===
# Persistent disk:
#   File: TEST_DATA_SELECTEL_PV_2026
#   MD5:  <hash>
# Temporary disk:
#   File: TEST_DATA_SELECTEL_PV_2026
#   MD5:  <hash>
# === Done ===
```

После успешной инициализации Job можно удалить.

```bash
kubectl delete job pv-init-once -n pv-test
```

#### Шаг 5: Деплой тестового сервиса

Применяем deployment, service и ingress.

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml

kubectl rollout status deployment/pv-test -n pv-test
```

Проверяем логи init-контейнера.

```bash
kubectl logs -n pv-test -l app=pv-test -c check-volumes

# Ожидаемый вывод:
# === Checking Persistent ===
# Persistent: OK (checksum matches)
# === Checking Temporary ===
# Temporary: OK (checksum matches)
# === Done ===
```

#### Шаг 6: Проверка работы сервиса

Открываем домен в браузере.

```text
https://pv-test.staging.platform.zhukovsd.it
```

Ожидаем увидеть:

- `Persistent Volume (Retain): OK: <md5-hash>`
- `Temporary Volume (Delete): OK: <md5-hash>`

Проверяем также содержимое файлов напрямую.

```bash
kubectl exec -n pv-test -it deployment/pv-test -- ls -lah /usr/share/nginx/html/persistent
kubectl exec -n pv-test -it deployment/pv-test -- cat /usr/share/nginx/html/persistent/result.txt
```

#### Шаг 7: Тест 1 – перезапуск Pod

Проверяем, что данные сохраняются при перезапуске Pod.

```bash
kubectl delete pod -n pv-test -l app=pv-test

kubectl get pods -n pv-test -w
```

После запуска нового Pod:

- Оба тома должны продолжать показывать `OK`.

#### Шаг 8: Тест 2 – пересоздание Deployment

Проверяем, что данные сохраняются при удалении и пересоздании Deployment.

```bash
kubectl delete deployment pv-test -n pv-test

kubectl apply -f deployment.yaml

kubectl rollout status deployment/pv-test -n pv-test
```

После пересоздания Deployment:

- Оба тома должны продолжать показывать `OK`.

#### Шаг 9: Тест 3 – удаление PVC

Цель – показать, что при удалении PVC:

- Retain-диск остаётся в Selectel
- Delete-диск удаляется

##### 9.1. Сохраняем ID дисков

```bash
kubectl get pv -o custom-columns=NAME:.metadata.name,VOLUMEHANDLE:.spec.csi.volumeHandle,POLICY:.spec.persistentVolumeReclaimPolicy

# Пример вывода:
# NAME                       VOLUMEHANDLE                             POLICY
# pvc-...-persistent         983a3f82-17ae-49a0-8f62-7374663a682e     Retain
# pvc-2ace5262-0f9a-4001...  <id-temporary>                            Delete

export PERSISTENT_VOLUME_ID="983a3f82-17ae-49a0-8f62-7374663a682e"
```

##### 9.2. Удаляем PVC

```bash
kubectl delete deployment pv-test -n pv-test

kubectl delete pvc pv-test-persistent pv-test-temporary -n pv-test

sleep 10

kubectl get pv

# Ожидаемый результат:
# Persistent PV (Retain) – в статусе Released
# Temporary PV (Delete) – отсутствует
```

##### 9.3. Проверяем диски в панели Selectel

В панели управления Selectel (`my.selectel.ru`) в разделе дисков:

- Persistent диск (Retain) – остался
- Temporary диск (Delete) – удалён

#### Шаг 10: Тест 4 – восстановление Retain диска

Создаём PV, который указывает на уже существующий диск в Selectel, и привязываем к нему PVC.

##### 10.1. Создание PV для существующего диска

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-test-persistent-restored
  annotations:
    pv.kubernetes.io/provisioned-by: cinder.csi.openstack.org
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: selectel-hdd-retain
  csi:
    driver: cinder.csi.openstack.org
    fsType: ext4
    volumeHandle: ${PERSISTENT_VOLUME_ID} # нужно добавить ID который мы ранее сохранили!
  volumeMode: Filesystem
EOF

kubectl get pv pv-test-persistent-restored

# Статус должен быть Available.
```

##### 10.2. Привязка PVC к созданному PV

```bash
kubectl delete pvc pv-test-persistent -n pv-test 2>/dev/null || true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pv-test-persistent
  namespace: pv-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: selectel-hdd-retain
  volumeName: pv-test-persistent-restored
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc pv-test-persistent -n pv-test

# PVC должен быть Bound к pv-test-persistent-restored.
```

##### 10.3. Повторный запуск приложения

```bash
kubectl apply -f deployment.yaml

kubectl rollout status deployment/pv-test -n pv-test

kubectl logs -n pv-test -l app=pv-test -c check-volumes

# Ожидаемый вывод:
# === Checking Persistent ===
# Persistent: OK (checksum matches)
# === Checking Temporary ===
# Temporary: File NOT FOUND
# === Done ===
```

В браузере для persistent тома снова будет `OK`, что подтверждает восстановление данных с Retain диска. Для temporary тома останется ошибка, так как диск был удалён окончательно.

#### Шаг 11: Стоимость

Используемые ресурсы:

- 2 HDD диска по 1GiB в зоне ru-7 (`basic.ru-7`)

При цене ~1 ₽ за 1GiB/месяц:

- Базовая конфигурация: 2 ₽/месяц

Итого максимум: около 2 ₽/месяц.

##### Сравнение с SSD

| Тип диска | Стоимость 1 GB/мес | Стоимость проекта |
|-----------|-------------------|------------------|
| **HDD (basic)** | ~1 ₽ | 2 ₽/мес |
| **SSD (fast)** | ~3 ₽ | 6 ₽/мес |
