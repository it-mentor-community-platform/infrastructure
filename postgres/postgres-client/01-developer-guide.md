### Инструкция для разработчиков: Доступ к PostgreSQL через kubectl + DBeaver

#### Введение

Эта инструкция поможет вам настроить доступ к PostgreSQL базе данных через безопасный туннель Kubernetes.

**Что вам понадобится:**
- Windows или macOS компьютер
- Файл `kubeconfig-<ваше-имя>.yaml` (получите у DevOps команды)
- 15-20 минут времени

**Как это работает:**
```
DBeaver → localhost:5432 → kubectl port-forward → Kubernetes Pod → PostgreSQL Selectel
```

---

### Шаг 1: Установка kubectl

##### Windows: Установка через Chocolatey

```powershell
# Открыть PowerShell от имени администратора

# Установить Chocolatey (если ещё не установлен)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Закрыть и открыть НОВОЕ окно PowerShell от администратора

# Установить kubectl
choco install kubernetes-cli -y

# Проверить установку
kubectl version --client
```

**Ожидаемый вывод:**
```
Client Version: v1.35.0
```

##### macOS: Установка через Homebrew

```bash
# Открыть Terminal

# Установить Homebrew (если ещё не установлен)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Установить kubectl
brew install kubectl

# Проверить установку
kubectl version --client
```

**Ожидаемый вывод:**
```
Client Version: v1.35.0
```

---

### Шаг 2: Настройка kubeconfig

##### Получение файла

Запросите у DevOps команды:
- Файл: `kubeconfig-<ваше-имя>.yaml`

##### Установка kubeconfig

**Windows (PowerShell):**
```powershell
# Создать папку .kube
mkdir $env:USERPROFILE\.kube -Force

# Скопировать полученный файл
# Вариант 1: Если файл в Downloads
Copy-Item $env:USERPROFILE\Downloads\kubeconfig-ivan-petrov.yaml $env:USERPROFILE\.kube\config

# Вариант 2: Вручную через проводник
# Скопировать файл в: C:\Users\<ВашеИмя>\.kube\config
```

**macOS (Terminal):**
```bash
# Создать папку .kube
mkdir -p ~/.kube

# Скопировать полученный файл
# Вариант 1: Если файл в Downloads
cp ~/Downloads/kubeconfig-ivan-petrov.yaml ~/.kube/config

# Вариант 2: Указать полный путь
cp /path/to/kubeconfig-ivan-petrov.yaml ~/.kube/config

# Установить правильные права доступа
chmod 600 ~/.kube/config
```

##### Проверка подключения

**Windows (PowerShell) / macOS (Terminal):**
```bash
# Проверить конфигурацию
kubectl config view

# Проверить доступ к кластеру
kubectl get namespaces

# Проверить postgres namespace
kubectl get pods -n postgres
```

**Ожидаемый вывод последней команды:**
```
NAME                               READY   STATUS    RESTARTS   AGE
postgres-client-xxxxxxxxxx-xxxxx   1/1     Running   0          Xh
```

✅ Если видите postgres-client Pod - всё настроено правильно!

---

### Шаг 3: Установка DBeaver

##### Скачать установщик

**Windows:**
1. Перейти на https://dbeaver.io/download/
2. Скачать **DBeaver Community Edition for Windows**
3. Запустить установщик
4. Следовать инструкциям (Next → Next → Install)

**macOS:**
1. Перейти на https://dbeaver.io/download/
2. Скачать **DBeaver Community Edition for macOS**
3. Открыть DMG файл
4. Перетащить DBeaver в папку Applications

---

### Шаг 4: Создание туннеля к PostgreSQL

##### Запуск port-forward

**Windows (PowerShell) / macOS (Terminal):**
```bash
# НЕ от администратора
kubectl port-forward -n postgres svc/postgres-client 5432:5432
```

**Ожидаемый вывод:**
```
Forwarding from 127.0.0.1:5432 -> 5432
Forwarding from [::1]:5432 -> 5432
Handling connection for 5432
Handling connection for 5432
```

**⚠️ ВАЖНО:**
- ✅ Оставьте это окно **открытым**
- ✅ Туннель работает пока окно не закрыто
- ✅ Для остановки нажмите `Ctrl+C`
- ❌ НЕ закрывайте окно во время работы с базой

##### Если порт 5432 занят

```bash
# Использовать другой порт (например 15432)
kubectl port-forward -n postgres svc/postgres-client 15432:5432

# В DBeaver укажите порт 15432 вместо 5432
```

---

### Шаг 5: Настройка подключения в DBeaver

##### Создание нового подключения

1. **Запустить DBeaver**

2. **Database** → **New Database Connection** (или `Ctrl+N` / `Cmd+N` на macOS)

3. **Выбрать PostgreSQL** → **Next**

4. **Заполнить параметры подключения:**

   | Параметр | Значение |
   |----------|----------|
   | Host | `localhost` |
   | Port | `5432` |
   | Database | `db_main` |
   | Username | `<ваш_пользователь>` |
   | Password | `<ваш_пароль>` |

   **Примеры Username:**
   - Для схемы `auth_service_staging`: `auth_service_staging_app`
   - Для схемы `profile_service_prod`: `profile_service_prod_app`
   - Для admin доступа: `admin`

5. **Нажать "Test Connection..."**
   - Если попросит скачать драйвер → нажать **Download**
   - Должно появиться: ✅ **Connected**

6. **Нажать "Finish"**

---

### Безопасность

##### Важные правила

- ✅ **НЕ коммитить** kubeconfig в Git
- ✅ **НЕ отправлять** kubeconfig в публичные каналы
- ✅ **НЕ хранить** пароли в открытом виде
- ✅ **Использовать** только рабочий компьютер
- ✅ **Закрывать** туннель после работы

##### Срок действия токена

- Токен в kubeconfig действителен **1 год**
- После истечения - запросить новый файл у DevOps
- При потере файла - немедленно сообщить DevOps
