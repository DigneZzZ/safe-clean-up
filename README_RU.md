# 🧹 SafeClean [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Shell](https://img.shields.io/badge/Script-Bash-green.svg)](https://www.gnu.org/software/bash/) [![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)](#)

Надежный и настраиваемый скрипт для безопасной очистки Linux-систем.

---

## ⚙️ Возможности

- 🧼 **Комплексная очистка**: Docker, systemd-журналы, APT-кэш, Snap-версии, `/tmp`
- 🔒 **Безопасность**: Без удаления критичных файлов и с проверкой прав
- 📊 **Оценка перед действием**: Анализ и прогноз экономии места
- 🕒 **Планирование**: Поддержка `systemd` таймеров и `cron`
- 🧩 **Гибкая конфигурация**: Через параметры CLI, файлы или интерактивное меню
- 📝 **Логирование**: Поддержка `syslog`, включая формат JSON
- 🧪 **Тестовый режим**: Безопасная имитация всех действий
- 🔍 **Самотестирование**: Проверка зависимостей, логики и целостности

---

## 🚀 Быстрая установка

С `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

С `curl`:

```bash
bash <(curl -s https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

Из репозитория:

```bash
git clone https://github.com/DigneZzZ/safe-clean-up.git
cd safe-clean-up
chmod +x safeclean.sh
sudo ./safeclean.sh --install
```

---

## 📌 Основное использование

```bash
safeclean --help           # Показать справку
safeclean --dry-run        # Анализ без удаления
sudo safeclean             # Очистка с подтверждением
sudo safeclean --force     # Очистка без подтверждений
```

---

## 🛠️ Расширенные опции

```bash
safeclean --config                   # Интерактивное меню
safeclean --journal-days 7          # Срок хранения логов
safeclean --journal-size 300        # Максимальный размер логов (MB)
safeclean --keep-docker-images      # Не удалять образы Docker
safeclean --syslog --json-log       # Включить логирование в syslog
safeclean --test-mode               # Тест без изменений
```

---

## ⏱️ Планирование задач

```bash
# С использованием systemd
sudo safeclean --schedule-systemd daily

# Через cron
sudo safeclean --schedule weekly

# Удаление всех задач
sudo safeclean --unschedule
```

---

## ⚙️ Конфигурация

Файл конфигурации можно указать вручную или использовать один из путей по умолчанию:

- **Системный**: `/etc/safeclean/config`
- **Пользовательский**: `~/.config/safeclean/config`

### Примеры параметров:

```ini
JOURNAL_DAYS=10
JOURNAL_SIZE=500
DOCKER_KEEP_IMAGES=false
TEMP_FILES_AGE=1
USE_SYSLOG=true
USE_JSON_LOG=true
CONFIRM_APT_AUTOREMOVE=true
```

---

## 🔐 Безопасность

- Проверка прав root
- Безопасная работа с `/tmp`
- Проверка открытых файлов
- Строгая обработка ошибок и зависимостей
- Встроенное логирование и self-test

---

## ✅ Совместимость

Работает на большинстве Linux-дистрибутивов:

- Ubuntu / Debian
- CentOS / RHEL
- Fedora
- Arch Linux
- openSUSE

**Требуется:** `bash >= 4.0`, `find`, `du`, `df`, `lsof`, `bc`  
**Желательно:** `systemd`, `logger`

---

## 🧪 Самотестирование

Проверка всех ключевых компонентов:

```bash
safeclean --self-test
```

---

## 📄 Лицензия

Проект распространяется под лицензией [MIT](LICENSE).

---

## 🤝 Вклад

PR’ы, багрепорты и предложения приветствуются! Убедитесь, что ваши изменения протестированы, и соответствуют стилю проекта.
```
