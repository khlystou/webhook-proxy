# Webhook Proxy

Минималистичный HTTPS-прокси для приема webhook-запросов и перенаправления их на внешний сервер.

Проект автоматически:

* Устанавливает и запускает Nginx в Docker.
* Получает SSL-сертификат Let's Encrypt через Certbot.
* Настраивает автоматическое продление сертификатов.
* Принимает только POST-запросы на `/webhook`.
* Проксирует запросы на удаленный endpoint.
* Передает тело запроса и все заголовки.
* Возвращает `404 Not Found` для всех остальных URL.
* Возвращает `405 Method Not Allowed` для любых методов кроме POST.
* Ограничивает размер тела запроса до 5 МБ.
* Отключает access-логи Nginx.

---

## Схема работы

```text
Client
  |
  | POST https://webhook.example.com/webhook
  v
Nginx (Docker)
  |
  | HTTPS Proxy
  v
https://target.example.com/api/webhook
```

---

## Требования

* Linux сервер
* Docker
* Docker Compose
* Доменное имя, указывающее на сервер
* Открытые порты:

  * 80/tcp
  * 443/tcp

---

## Установка Docker

Ubuntu / Debian:

```bash
apt update
apt install -y docker.io docker-compose-plugin
systemctl enable docker
systemctl start docker
```

Проверка:

```bash
docker --version
docker compose version
```

---

## Установка

Скачать скрипт

```bash
wget -O install.sh "https://raw.githubusercontent.com/khlystou/webhook-proxy/refs/heads/main/install.sh";
```

Сделайте скрипт исполняемым:

```bash
chmod +x install.sh
```

Запустите установку:

```bash
sudo ./install.sh <server-domain> <target-domain>
```

Пример:

```bash
sudo ./install.sh webhook.example.com api.example.com
```

где:

* `webhook.example.com` — домен, который будет принимать webhook.
* `api.example.com` — целевой сервер для проксирования.

---

## Результат

После установки будет доступен endpoint:

```text
https://webhook.example.com/webhook
```

Все POST-запросы будут перенаправляться на:

```text
https://api.example.com/api/webhook
```

---

## Ограничения

### Разрешено

```http
POST /webhook
```

### Запрещено

```http
GET /webhook
PUT /webhook
PATCH /webhook
DELETE /webhook
```

Ответ:

```http
405 Method Not Allowed
```

---

### Любой другой URL

Примеры:

```http
GET /
GET /test
POST /api
POST /anything
```

Ответ:

```http
404 Not Found
```

---

## Ограничение размера запроса

Максимальный размер тела запроса:

```text
5 MB
```

При превышении лимита сервер вернет:

```http
413 Request Entity Too Large
```

---

## SSL-сертификаты

Для выдачи сертификатов используется Let's Encrypt.

Сертификат автоматически выпускается во время установки.

---

## Автоматическое продление сертификатов

Во время установки создается cron-задача:

```text
17 3 * * * root
```

Каждый день в 03:17 выполняется:

1. Проверка сертификатов.
2. Продление при необходимости.
3. Перезапуск Nginx.

---

## Проверка продления сертификатов

Ручная проверка:

```bash
cd /opt/webhook-proxy

docker compose run --rm certbot renew --dry-run
```

---

## Структура проекта

```text
/opt/webhook-proxy
├── docker-compose.yml
├── nginx
│   └── conf.d
│       └── webhook.conf
└── certbot
    ├── conf
    └── www
```

---

## Управление сервисом

Переход в каталог проекта:

```bash
cd /opt/webhook-proxy
```

Запуск:

```bash
docker compose up -d
```

Остановка:

```bash
docker compose down
```

Перезапуск:

```bash
docker compose restart
```

Просмотр контейнеров:

```bash
docker ps
```

---

## Безопасность

Проект специально сделан максимально простым:

* Только один публичный endpoint.
* Только HTTPS.
* Только POST.
* Нет статических файлов.
* Нет панели управления.
* Нет открытых API кроме `/webhook`.
* Логи запросов отключены.

Это снижает поверхность атаки и подходит для приема webhook от внешних сервисов.
