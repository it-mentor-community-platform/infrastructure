### Установка NGINX Ingress Controller

1. Устанавливать будем через helm. Версии на момент установки: 

- helm-чарта `ingress-nginx-4.14.1`
- `ingress-controller 1.14.1`

1.1 Добавляем Helm репозиторий
```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```
1.2 Получаем дефолтные значения values.yaml.

`helm show values ingress-nginx/ingress-nginx --version 4.11.3 > values.yaml`

Это создаст файл values.yaml с дефолтной конфигурацией.

2. Настройка values ingress контроллера. Меняем указанные параметры:
```
controller:
  # Количество реплик для отказоустойчивости
  replicaCount: 2
```
Ресурсы контроллера
```
  resources:
    requests:
      cpu: 100m
      memory: 90Mi
    limits:
      cpu: 100m
      memory: 90Mi
```
Настройка Service типа LoadBalancer (ищем в values тип сервиса -LoadBalancer)
```
  service:
    ports:
      http: 80
      https: 443
```
    
    # Тип внешнего трафика
    externalTrafficPolicy: Local

3. Установка ingress-controller

```
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.11.3 \
  --namespace ingress-nginx \
  --create-namespace \
  -f values.yaml
```
4. Проверка установки
`kubectl get pods -n ingress-nginx`
Результат будет вида:
```
# NAME                                        READY   STATUS    RESTARTS   AGE
# ingress-nginx-controller-xxxxx              1/1     Running   0          2m
# ingress-nginx-controller-yyyyy              1/1     Running   0          2m
```
и смотрим балансер (нам нужно, чтобы поле EXTERNAL IP было с выданным IP)
```
➜  kubectl get svc -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   10.103.210.64    81.177.222.18   80:30573/TCP,443:31825/TCP   4m
ingress-nginx-controller-admission   ClusterIP      10.105.114.115   <none>          443/TCP                      4m
```

Если вы увидели IP - значит все выполнено верно и ваш ингресс настроен для работы.

### Тестирование NGINX Ingress Controller
1. **Деплой двух тестовых сервиса.**
   - `nginx-test` и `tomcat-test` в одноименных namespace. Файлы сервисов можно найти в репозитории в папке `/test-apps/*`
     
2. **Приобритение/регистрация домена.**
   На поддоменах которого будут хостится все наши сервиса кластера. Сделать это можно у соотвествующих провайдеров. Мы для примера возьмем текущий домент stage окружения - `staging.platform.zhukovsd.it`
   
3. **Регистрация доменов и создание доменной зоны.**
   После того, как у нас появился свой домен, нужно:
   - зайти в панель управления Selectel -> Продукты -> DNS-хостинг
   - нажать _Добавить зону_ и проставить туда наш домен (обязательно! с точкой на конце). На нашем примере - `staging.platform.zhukovsd.it.`
   - после этого у провайдера, у которого вы регистрировали/приобретали домен необходимо проставить ns-сервера. У селектела это - NS-серверы DNS-хостинга (actual) — a.ns.selectel.ru, b.ns.selectel.ru, c.ns.selectel.ru, d.ns.selectel.ru
   - далее заходим в доменную зону и добавляем туда 2 A-записи, которые будут вести на ip-адрес нашего балансера. В нашем примере это - `nginx-test.staging.platform.zhukovsd.it.` и `tomcat-test.staging.platform.zhukovsd.it.`. TTL оставляем по умолчанию.
   - Обновление DNS может занимать от 15 минут до 24 часов в худшем случае. Если тестовые сервисы начинают отдавать свои рабочие стартовые страницы по зарегестрированным доменам - значит DNS заработал.
   - на текущий момент актуальную информацию по DNS в Selectel можно прочитать: https://docs.selectel.ru/dns-hosting/ 
  
4. Тест ингресса. После регистрации доменов можно пооткрывать несколько раз наши страницы. В нашем примере это http://nginx-test.staging.platform.zhukovsd.it/ и http://tomcat-test.staging.platform.zhukovsd.it/
   Для автоматизации задачи, можно написать небольшой нагрузочный тест. Цель - убедиться, что наша цепочка ингрессов и сервисов отрабатывает. После проведения теста смотрим
   - Логи вшнешнего ингресс-контроллера `kubectl logs -n ingress-nginx ingress-nginx-controller-7d7f5d6d94-ch4q6 --tail=5`
   - Логи наших тестовых сервисов `kubectl logs -n nginx-test nginx-86bd9669d5-7hs5j --tail=5`
     Если в логах вы видите 200 и 304 коды - значит все отлично. Если что-то отличное - то ищете, в чем проблема.
   
