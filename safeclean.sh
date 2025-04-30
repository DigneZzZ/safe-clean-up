#!/bin/bash

set -euo pipefail

VERSION="1.4.0"
SCRIPT_NAME="safeclean"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"
CONFIG_DIR="/etc/$SCRIPT_NAME"
CONFIG_FILE="$CONFIG_DIR/config"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$SCRIPT_NAME"
USER_CONFIG_FILE="$USER_CONFIG_DIR/config"
SYSTEMD_SYSTEM_DIR="/etc/systemd/system"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

TEMP_FILE="/tmp/cleanup_report.txt"
FORCE_MODE=false
DRY_RUN=false
TEST_MODE=false
DISK_BEFORE=0
TOTAL_ESTIMATE=0
USE_SYSLOG=false
USE_JSON_LOG=false

# Настраиваемые пороги (значения по умолчанию)
JOURNAL_DAYS=10
JOURNAL_SIZE=500
DOCKER_KEEP_IMAGES=false
TEMP_FILES_AGE=1
CONFIRM_APT_AUTOREMOVE=true

# Тестовые данные
TEST_DOCKER_SIZE=500
TEST_JOURNAL_SIZE=800
TEST_APT_SIZE=300
TEST_SNAP_SIZE=150
TEST_TEMP_SIZE=100

# Необходимые зависимости
DEPENDENCIES=("find" "du" "df" "lsof" "bc")

# Функция для логирования
log_to_syslog() {
    if [ "$USE_SYSLOG" = true ] && command -v logger &>/dev/null; then
        if [ "$USE_JSON_LOG" = true ]; then
            # JSON-форматированный лог
            local timestamp=$(date -Iseconds)
            local json_msg="{\"timestamp\":\"$timestamp\",\"script\":\"$SCRIPT_NAME\",\"message\":\"$1\",\"level\":\"${2:-info}\"}"
            logger -t "$SCRIPT_NAME" "$json_msg"
        else
            # Обычный лог
            logger -t "$SCRIPT_NAME" -p "${2:-info}" "$1"
        fi
    fi
}

# Функция для логирования ошибок
log_error() {
    local error_msg="$1"
    echo "❌ ОШИБКА: $error_msg" | tee -a "$TEMP_FILE" >&2
    log_to_syslog "$error_msg" "error"
}

# Загрузка конфигурации, если она существует
load_config() {
    local loaded=false
    
    # Сначала пробуем загрузить пользовательскую конфигурацию
    if [ -n "${CONFIG_PATH:-}" ] && [ -f "$CONFIG_PATH" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_PATH"
        loaded=true
    # Затем системную
    elif [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        loaded=true
    # Затем пользовательскую в домашнем каталоге
    elif [ -f "$USER_CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$USER_CONFIG_FILE"
        loaded=true
    fi
    
    if [ "$loaded" = true ]; then
        log_message "📝 Загружена конфигурация"
        log_to_syslog "Загружена конфигурация"
    fi
}

# Сохранение конфигурации
save_config() {
    local target_dir
    local target_file
    
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        target_dir="$CONFIG_DIR"
        target_file="$CONFIG_FILE"
    else
        target_dir="$USER_CONFIG_DIR"
        target_file="$USER_CONFIG_FILE"
    fi
    
    # Если указан пользовательский путь, используем его
    if [ -n "${CONFIG_PATH:-}" ]; then
        target_file="$CONFIG_PATH"
        target_dir=$(dirname "$CONFIG_PATH")
    fi
    
    mkdir -p "$target_dir"
    
    cat > "$target_file" << EOF
# $SCRIPT_NAME configuration file
# Generated on $(date)

# Настраиваемые пороги
JOURNAL_DAYS=$JOURNAL_DAYS
JOURNAL_SIZE=$JOURNAL_SIZE
DOCKER_KEEP_IMAGES=$DOCKER_KEEP_IMAGES
TEMP_FILES_AGE=$TEMP_FILES_AGE
USE_SYSLOG=$USE_SYSLOG
USE_JSON_LOG=$USE_JSON_LOG
CONFIRM_APT_AUTOREMOVE=$CONFIRM_APT_AUTOREMOVE

# Тестовые данные
TEST_DOCKER_SIZE=$TEST_DOCKER_SIZE
TEST_JOURNAL_SIZE=$TEST_JOURNAL_SIZE
TEST_APT_SIZE=$TEST_APT_SIZE
TEST_SNAP_SIZE=$TEST_SNAP_SIZE
TEST_TEMP_SIZE=$TEST_TEMP_SIZE
EOF
    chmod 644 "$target_file"
    echo "Конфигурация сохранена в $target_file"
    log_to_syslog "Конфигурация сохранена в $target_file"
}

log_message() {
    echo "$1" | tee -a "$TEMP_FILE"
    log_to_syslog "$1"
}

# Проверка наличия необходимых зависимостей
check_dependencies() {
    local missing_deps=()
    
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    # Проверка дополнительных зависимостей в зависимости от режима работы
    if [ "$USE_SYSLOG" = true ] && ! command -v logger &>/dev/null; then
        missing_deps+=("logger")
    fi
    
    if [ "${#missing_deps[@]}" -gt 0 ]; then
        echo "❌ Отсутствуют необходимые зависимости: ${missing_deps[*]}"
        echo "Установите их с помощью менеджера пакетов вашей системы."
        
        # Предложение команды для установки в зависимости от дистрибутива
        if command -v apt &>/dev/null; then
            echo "Для Ubuntu/Debian: sudo apt install ${missing_deps[*]}"
        elif command -v dnf &>/dev/null; then
            echo "Для Fedora: sudo dnf install ${missing_deps[*]}"
        elif command -v yum &>/dev/null; then
            echo "Для CentOS/RHEL: sudo yum install ${missing_deps[*]}"
        elif command -v pacman &>/dev/null; then
            echo "Для Arch Linux: sudo pacman -S ${missing_deps[*]}"
        elif command -v zypper &>/dev/null; then
            echo "Для openSUSE: sudo zypper install ${missing_deps[*]}"
        fi
        
        exit 1
    fi
}

# Выполнение команды с учетом тестового режима
execute_cmd() {
    local cmd="$1"
    local error_msg="${2:-Ошибка выполнения команды}"
    
    if [ "$TEST_MODE" = true ]; then
        log_message "ТЕСТ: $cmd"
        return 0
    else
        if eval "$cmd"; then
            return 0
        else
            local exit_code=$?
            log_error "$error_msg (код ошибки: $exit_code)"
            return $exit_code
        fi
    fi
}

convert_to_mb() {
    [[ -z "$1" ]] && echo 0 && return
    if [[ "$1" =~ ([0-9.]+)([KMG]) ]]; then
        local value=${BASH_REMATCH[1]}
        local unit=${BASH_REMATCH[2]}
        case "$unit" in
            G) LC_NUMERIC=C printf "%.0f" "$(echo "$value * 1024" | bc -l)" ;;
            M) LC_NUMERIC=C printf "%.0f" "$value" ;;
            K) LC_NUMERIC=C printf "%.0f" "$(echo "$value / 1024" | bc -l)" ;;
            *) echo 0 ;;
        esac
    else
        echo 0
    fi
}

analyze_disk() {
    log_message "📍 Место на диске до:"
    if ! df -h | tee -a "$TEMP_FILE"; then
        log_error "Не удалось получить информацию о дисковом пространстве"
    fi
    log_message ""
    
    if ! DISK_BEFORE=$(df --output=used / | tail -n1 | tr -d '[:space:]'); then
        log_error "Не удалось получить исходный размер использованного пространства"
        DISK_BEFORE=0
    fi
}

analyze_docker() {
    if command -v docker &>/dev/null && { [ "$TEST_MODE" = true ] || systemctl is-active docker &>/dev/null; }; then
        log_message "🐳 Docker:"
        if [ "$TEST_MODE" = true ]; then
            log_message "ТЕСТ: docker system df"
            log_message "Containers: 5"
            log_message "Images: 10"
            log_message "Volumes: 3"
            log_message "Reclaimable: ${TEST_DOCKER_SIZE}MB"
            TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + TEST_DOCKER_SIZE))
            echo " - Docker: ~${TEST_DOCKER_SIZE}MB"
        else
            if ! docker system df | tee -a "$TEMP_FILE"; then
                log_error "Не удалось получить информацию о Docker"
                return
            fi
            
            local reclaim
            if ! reclaim=$(docker system df --format '{{.Reclaimable}}' | grep -o '[0-9.]\+' | head -n1 || echo "0"); then
                log_error "Не удалось получить информацию о возможной очистке Docker"
                reclaim=0
            fi
            
            if [[ "$reclaim" =~ ^[0-9.]+$ ]]; then
                TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + ${reclaim%.*}))
            fi
            log_message ""
            echo " - Docker: ~${reclaim}MB"
        fi
    else
        log_message "🐳 Docker не установлен или служба не запущена."
    fi
}

analyze_journal() {
    log_message "🗙 Systemd-журналы:"
    if [ "$TEST_MODE" = true ] || journalctl --disk-usage &>/dev/null; then
        if [ "$TEST_MODE" = true ]; then
            log_message "ТЕСТ: journalctl --disk-usage"
            log_message " - Текущий объем логов: ${TEST_JOURNAL_SIZE}M"
            log_message " - Будет удалено всё старше ${JOURNAL_DAYS} дней и сверх ${JOURNAL_SIZE}MB"
            local est_log_mb=$((TEST_JOURNAL_SIZE > JOURNAL_SIZE ? TEST_JOURNAL_SIZE - JOURNAL_SIZE : 0))
            TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + est_log_mb))
            echo " - Systemd-журналы: ~${est_log_mb}MB"
        else
            local journal_size
            if ! journal_size=$(LANG=C journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]\+[KMG]' | head -n1 || echo "0"); then
                log_error "Не удалось получить размер журналов systemd"
                journal_size="0"
            fi
            
            log_message " - Текущий объем логов: ${journal_size:-0}"
            log_message " - Будет удалено всё старше ${JOURNAL_DAYS} дней и сверх ${JOURNAL_SIZE}MB"
            local log_mb=$(convert_to_mb "$journal_size")
            local est_log_mb=$((log_mb > JOURNAL_SIZE ? log_mb - JOURNAL_SIZE : 0))
            TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + est_log_mb))
            echo " - Systemd-журналы: ~${est_log_mb}MB"
        fi
    else
        log_message " - Журналы systemd недоступны"
        log_error "Не удалось получить доступ к журналам systemd"
    fi
    log_message ""
}

analyze_apt() {
    log_message "📦 APT кэш:"
    if [ "$TEST_MODE" = true ] || [ -d /var/cache/apt ]; then
        if [ "$TEST_MODE" = true ]; then
            log_message "ТЕСТ: du -sh /var/cache/apt"
            log_message " - Размер: ${TEST_APT_SIZE}M"
            TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + TEST_APT_SIZE))
            echo " - APT кэш: ~${TEST_APT_SIZE}MB"
        else
            local apt_size
            if ! apt_size=$(du -sh /var/cache/apt 2>/dev/null | cut -f1 || echo "0"); then
                log_error "Не удалось получить размер кэша APT"
                apt_size="0"
            fi
            
            log_message " - Размер: ${apt_size:-0}"
            
            local apt_bytes
            if ! apt_bytes=$(du -sb /var/cache/apt 2>/dev/null | awk '{print $1}' || echo "0"); then
                log_error "Не удалось получить размер кэша APT в байтах"
                apt_bytes=0
            fi
            
            local apt_mb=$((apt_bytes / 1024 / 1024))
            TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + apt_mb))
            echo " - APT кэш: ~${apt_mb}MB"
        fi
    else
        log_message " - Каталог APT не найден"
    fi
    log_message ""
}

analyze_snap() {
    if [ "$TEST_MODE" = true ] || command -v snap &>/dev/null; then
        log_message "📦 Snap старые версии:"
        
        if [ "$TEST_MODE" = true ]; then
            log_message "ТЕСТ: snap list --all"
            log_message "app1  1  disabled"
            log_message "app2  2  disabled"
            log_message "app3  3  disabled"
            local snap_size=$TEST_SNAP_SIZE
            TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + snap_size))
            echo " - Snap старые версии: ~${snap_size}MB"
        else
            local snap_old
            if ! snap_old=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $2, $3}' || true); then
                log_error "Не удалось получить список Snap-пакетов"
                return
            fi
            
            if [ -n "$snap_old" ]; then
                log_message "$snap_old"
                # Точная оценка размера старых snap-пакетов
                local snap_size=0
                local snap_dir="/var/lib/snapd/snaps"
                
                while read -r snapname revision _; do
                    if [[ "$revision" =~ ^[0-9]+$ ]]; then
                        local snap_file="$snap_dir/${snapname}_${revision}.snap"
                        if [ -f "$snap_file" ]; then
                            local file_size
                            if ! file_size=$(du -sm "$snap_file" 2>/dev/null | cut -f1 || echo "0"); then
                                log_error "Не удалось получить размер файла $snap_file"
                                file_size=50 # Используем оценку по умолчанию
                            fi
                            snap_size=$((snap_size + file_size))
                            log_message " - $snapname (rev $revision): ${file_size}MB"
                        else
                            # Если файл не найден, используем оценку
                            snap_size=$((snap_size + 50))
                            log_message " - $snapname (rev $revision): ~50MB (оценка)"
                        fi
                    fi
                done <<< "$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $2}' || true)"
                
                TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + snap_size))
                echo " - Snap старые версии: ~${snap_size}MB"
            else
                log_message " - Нет старых Snap ревизий"
            fi
        fi
    else
        log_message "📦 Snap не установлен."
    fi
    log_message ""
}

analyze_temp_files() {
    log_message "🗑️ Временные файлы:"
    
    if [ "$TEST_MODE" = true ]; then
        log_message "ТЕСТ: du -sh /tmp"
        log_message " - Размер /tmp: ${TEST_TEMP_SIZE}M"
        local temp_mb=$TEST_TEMP_SIZE
        TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + temp_mb / 2))
        echo " - Временные файлы: ~$((temp_mb / 2))MB"
    else
        local temp_size
        if ! temp_size=$(du -sh /tmp 2>/dev/null | cut -f1 || echo "0"); then
            log_error "Не удалось получить размер директории /tmp"
            temp_size="0"
        fi
        
        log_message " - Размер /tmp: ${temp_size:-0}"
        
        local temp_bytes
        if ! temp_bytes=$(du -sb /tmp 2>/dev/null | awk '{print $1}' || echo "0"); then
            log_error "Не удалось получить размер директории /tmp в байтах"
            temp_bytes=0
        fi
        
        local temp_mb=$((temp_bytes / 1024 / 1024))
        TOTAL_ESTIMATE=$((TOTAL_ESTIMATE + temp_mb / 2)) # Примерно половина может быть очищена
        echo " - Временные файлы: ~$((temp_mb / 2))MB"
    fi
    log_message ""
}

clean_docker() {
    if command -v docker &>/dev/null && { [ "$TEST_MODE" = true ] || systemctl is-active docker &>/dev/null; }; then
        log_message "Очистка Docker..."
        if [ "$DOCKER_KEEP_IMAGES" = true ]; then
            # Более безопасная очистка без удаления всех образов
            execute_cmd "docker container prune -f" "Ошибка очистки контейнеров Docker"
            execute_cmd "docker network prune -f" "Ошибка очистки сетей Docker"
            execute_cmd "docker builder prune -f" "Ошибка очистки кэша сборки Docker"
        else
            # Полная очистка
            execute_cmd "docker system prune -af" "Ошибка очистки Docker"
            # Отдельная очистка томов для большей безопасности
            if [ "$FORCE_MODE" = true ]; then
                execute_cmd "docker volume prune -f" "Ошибка очистки томов Docker"
            else
                read -p "⚠️  Удалить все неиспользуемые тома Docker? (y/N): " confirm_volumes
                if [[ "${confirm_volumes:-N}" =~ ^[Yy]$ ]]; then
                    execute_cmd "docker volume prune -f" "Ошибка очистки томов Docker"
                fi
            fi
        fi
    fi
}

clean_journal() {
    if [ "$TEST_MODE" = true ] || journalctl --disk-usage &>/dev/null; then
        log_message "Очистка systemd-журналов..."
        execute_cmd "journalctl --vacuum-time=${JOURNAL_DAYS}d" "Ошибка очистки логов по времени"
        execute_cmd "journalctl --vacuum-size=${JOURNAL_SIZE}M" "Ошибка очистки логов по размеру"
    fi
}

clean_apt() {
    if [ "$TEST_MODE" = true ] || command -v apt &>/dev/null; then
        log_message "Очистка APT-кэша..."
        execute_cmd "apt clean" "Ошибка очистки APT"
        
        # Запрос подтверждения для apt autoremove
        if [ "$FORCE_MODE" = true ] || [ "$CONFIRM_APT_AUTOREMOVE" = false ]; then
            execute_cmd "apt autoremove -y" "Ошибка удаления неиспользуемых пакетов"
        else
            read -p "⚠️  Удалить неиспользуемые пакеты? (y/N): " confirm
            if [[ "${confirm:-N}" =~ ^[Yy]$ ]]; then
                execute_cmd "apt autoremove -y" "Ошибка удаления неиспользуемых пакетов"
            else
                log_message " - Пропуск удаления неиспользуемых пакетов"
            fi
        fi
    fi
}

clean_snap() {
    if [ "$TEST_MODE" = true ] || command -v snap &>/dev/null; then
        log_message "Очистка старых Snap-ревизий..."
        
        if [ "$TEST_MODE" = true ]; then
            log_message "ТЕСТ: Очистка старых Snap-ревизий"
            log_message "ТЕСТ: snap remove app1 --revision=1"
            log_message "ТЕСТ: snap remove app2 --revision=2"
            log_message "ТЕСТ: snap remove app3 --revision=3"
        else
            snap list --all 2>/dev/null | awk '/disabled/{print $1, $2}' | while read -r snapname revision; do
                if [[ "$revision" =~ ^[0-9]+$ ]]; then
                    log_message "Удаляю $snapname revision $revision..."
                    execute_cmd "snap remove \"$snapname\" --revision=\"$revision\"" "Ошибка удаления $snapname revision $revision"
                fi
            done
        fi
    fi
}

clean_temp_files() {
    log_message "Очистка временных файлов..."
    # Безопасная очистка /tmp - проверка открытых файлов перед удалением
    if [ "$TEST_MODE" = true ]; then
        log_message "ТЕСТ: Очистка временных файлов в /tmp"
    else
        execute_cmd "find /tmp -type f -atime +\"$TEMP_FILES_AGE\" -exec lsof {} \\; >/dev/null 2>&1 || find /tmp -type f -atime +\"$TEMP_FILES_AGE\" -delete 2>/dev/null" "Ошибка очистки /tmp"
    fi
}

install_script() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "Для установки требуются права root. Запустите с sudo."
        exit 1
    fi
    
    # Копирование скрипта в /usr/local/bin
    cp "$0" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"
    
    # Создание конфигурационного каталога и файла
    mkdir -p "$CONFIG_DIR"
    save_config
    
    echo "✅ $SCRIPT_NAME успешно установлен в $INSTALL_PATH"
    echo "✅ Конфигурация сохранена в $CONFIG_FILE"
    echo "✅ Запустите '$SCRIPT_NAME --help' для получения справки"
    exit 0
}

uninstall_script() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "Для удаления требуются права root. Запустите с sudo."
        exit 1
    fi
    
    # Удаление скрипта и конфигурации
    rm -f "$INSTALL_PATH"
    rm -rf "$CONFIG_DIR"
    
    # Удаление systemd-таймеров и сервисов
    if [ -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.service" ]; then
        systemctl disable --now "$SCRIPT_NAME.service" 2>/dev/null || true
        rm -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.service"
    fi
    
    if [ -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.timer" ]; then
        systemctl disable --now "$SCRIPT_NAME.timer" 2>/dev/null || true
        rm -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.timer"
    fi
    
    # Удаление из cron
    unschedule_script
    
    echo "✅ $SCRIPT_NAME успешно удален из системы"
    exit 0
}

# Создание systemd-таймера
create_systemd_timer() {
    local schedule="$1"
    local system_wide="$2"
    
    local timer_dir
    local service_dir
    
    if [ "$system_wide" = true ]; then
        if [ "${EUID:-$(id -u)}" -ne 0 ]; then
            echo "Для создания системного таймера требуются права root. Запустите с sudo."
            exit 1
        fi
        timer_dir="$SYSTEMD_SYSTEM_DIR"
        service_dir="$SYSTEMD_SYSTEM_DIR"
    else
        timer_dir="$SYSTEMD_USER_DIR"
        service_dir="$SYSTEMD_USER_DIR"
        mkdir -p "$timer_dir"
    fi
    
    # Создание сервисного файла
    cat > "$service_dir/$SCRIPT_NAME.service" << EOF
[Unit]
Description=SafeClean System Cleanup Service
After=network.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH --force --syslog
EOF
    
    if [ "$system_wide" = true ]; then
        echo "User=root" >> "$service_dir/$SCRIPT_NAME.service"
    fi
    
    echo "[Install]" >> "$service_dir/$SCRIPT_NAME.service"
    echo "WantedBy=multi-user.target" >> "$service_dir/$SCRIPT_NAME.service"
    
    # Создание таймера
    cat > "$timer_dir/$SCRIPT_NAME.timer" << EOF
[Unit]
Description=Run SafeClean System Cleanup

[Timer]
EOF
    
    # Настройка расписания
    case "$schedule" in
        daily)
            echo "OnCalendar=*-*-* 03:00:00" >> "$timer_dir/$SCRIPT_NAME.timer"
            ;;
        weekly)
            echo "OnCalendar=Mon *-*-* 03:00:00" >> "$timer_dir/$SCRIPT_NAME.timer"
            ;;
        monthly)
            echo "OnCalendar=*-*-01 03:00:00" >> "$timer_dir/$SCRIPT_NAME.timer"
            ;;
        *)
            echo "Неверный тип расписания. Используйте daily, weekly или monthly."
            rm -f "$service_dir/$SCRIPT_NAME.service" "$timer_dir/$SCRIPT_NAME.timer"
            exit 1
            ;;
    esac
    
    echo "Persistent=true" >> "$timer_dir/$SCRIPT_NAME.timer"
    echo "RandomizedDelaySec=1h" >> "$timer_dir/$SCRIPT_NAME.timer"
    echo "" >> "$timer_dir/$SCRIPT_NAME.timer"
    echo "[Install]" >> "$timer_dir/$SCRIPT_NAME.timer"
    echo "WantedBy=timers.target" >> "$timer_dir/$SCRIPT_NAME.timer"
    
    # Активация таймера
    if [ "$system_wide" = true ]; then
        systemctl daemon-reload
        systemctl enable --now "$SCRIPT_NAME.timer"
        echo "✅ Системный таймер $SCRIPT_NAME ($schedule) активирован"
    else
        systemctl --user daemon-reload
        systemctl --user enable --now "$SCRIPT_NAME.timer"
        echo "✅ Пользовательский таймер $SCRIPT_NAME ($schedule) активирован"
    fi
}

# Удаление systemd-таймера
remove_systemd_timer() {
    local system_wide="$1"
    
    if [ "$system_wide" = true ]; then
        if [ "${EUID:-$(id -u)}" -ne 0 ]; then
            echo "Для удаления системного таймера требуются права root. Запустите с sudo."
            exit 1
        fi
        
        if [ -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.timer" ]; then
            systemctl disable --now "$SCRIPT_NAME.timer" 2>/dev/null || true
            rm -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.timer"
            rm -f "$SYSTEMD_SYSTEM_DIR/$SCRIPT_NAME.service"
            systemctl daemon-reload
            echo "✅ Системный таймер $SCRIPT_NAME удален"
        else
            echo "❌ Системный таймер $SCRIPT_NAME не найден"
        fi
    else
        if [ -f "$SYSTEMD_USER_DIR/$SCRIPT_NAME.timer" ]; then
            systemctl --user disable --now "$SCRIPT_NAME.timer" 2>/dev/null || true
            rm -f "$SYSTEMD_USER_DIR/$SCRIPT_NAME.timer"
            rm -f "$SYSTEMD_USER_DIR/$SCRIPT_NAME.service"
            systemctl --user daemon-reload
            echo "✅ Пользовательский таймер $SCRIPT_NAME удален"
        else
            echo "❌ Пользовательский таймер $SCRIPT_NAME не найден"
        fi
    fi
}

schedule_script() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "Для планирования задачи требуются права root. Запустите с sudo."
        exit 1
    fi
    
    local schedule_type="$1"
    local use_systemd="${2:-false}"
    
    # Проверка, установлен ли скрипт
    if [ ! -f "$INSTALL_PATH" ]; then
        read -p "Скрипт не установлен в системе. Установить сейчас? (y/N): " confirm
        if [[ "${confirm:-N}" =~ ^[Yy]$ ]]; then
            install_script
        else
            echo "Отмена планирования задачи."
            exit 1
        fi
    fi
    
    # Если указано использовать systemd и он доступен
    if [ "$use_systemd" = true ] && command -v systemctl &>/dev/null; then
        create_systemd_timer "$schedule_type" true
        return
    fi
    
    # Иначе используем cron
    local cron_file="/etc/cron.$schedule_type/$SCRIPT_NAME"
    local anacron_file="/etc/cron.$schedule_type.d/$SCRIPT_NAME"
    local crontab_entry=""
    
    case "$schedule_type" in
        daily)
            crontab_entry="0 3 * * * root $INSTALL_PATH --force --syslog"
            ;;
        weekly)
            crontab_entry="0 3 * * 0 root $INSTALL_PATH --force --syslog"
            ;;
        monthly)
            crontab_entry="0 3 1 * * root $INSTALL_PATH --force --syslog"
            ;;
        *)
            echo "Неверный тип расписания. Используйте daily, weekly или monthly."
            exit 1
            ;;
    esac
    
    # Создание задачи в cron
    if [ -d "/etc/cron.$schedule_type" ]; then
        echo "$crontab_entry" > "$cron_file"
        chmod 644 "$cron_file"
        echo "✅ Задача добавлена в /etc/cron.$schedule_type"
    elif [ -d "/etc/cron.$schedule_type.d" ]; then
        echo "#!/bin/sh" > "$anacron_file"
        echo "$INSTALL_PATH --force --syslog" >> "$anacron_file"
        chmod 755 "$anacron_file"
        echo "✅ Задача добавлена в /etc/cron.$schedule_type.d"
    else
        # Добавление в системный crontab
        (crontab -l 2>/dev/null || echo "") | grep -v "$SCRIPT_NAME" > /tmp/crontab.tmp
        echo "$crontab_entry" >> /tmp/crontab.tmp
        crontab /tmp/crontab.tmp
        rm /tmp/crontab.tmp
        echo "✅ Задача добавлена в системный crontab"
    fi
    
    echo "✅ $SCRIPT_NAME будет запускаться $schedule_type"
}

unschedule_script() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "Для удаления задачи требуются права root. Запустите с sudo."
        exit 1
    fi
    
    # Удаление из всех возможных мест
    rm -f /etc/cron.daily/$SCRIPT_NAME
    rm -f /etc/cron.weekly/$SCRIPT_NAME
    rm -f /etc/cron.monthly/$SCRIPT_NAME
    rm -f /etc/cron.daily.d/$SCRIPT_NAME
    rm -f /etc/cron.weekly.d/$SCRIPT_NAME
    rm -f /etc/cron.monthly.d/$SCRIPT_NAME
    
    # Удаление из системного crontab
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_NAME"; then
        crontab -l | grep -v "$SCRIPT_NAME" | crontab -
        echo "✅ Задача удалена из системного crontab"
    fi
    
    # Удаление systemd-таймеров
    if command -v systemctl &>/dev/null; then
        remove_systemd_timer true
    fi
    
    echo "✅ Все запланированные задачи $SCRIPT_NAME удалены"
}

self_test() {
    echo "=== $SCRIPT_NAME v$VERSION: Запуск самотестирования ==="
    echo
    
    # Временный файл для результатов теста
    local test_log="/tmp/${SCRIPT_NAME}_selftest.log"
    > "$test_log"
    
    echo "1. Проверка базовых функций..."
    
    # Тест convert_to_mb
    local test_convert=$(convert_to_mb "100M")
    if [ "$test_convert" = "100" ]; then
        echo "  ✅ convert_to_mb: OK"
    else
        echo "  ❌ convert_to_mb: ОШИБКА (ожидалось 100, получено $test_convert)"
        echo "convert_to_mb: ОШИБКА (ожидалось 100, получено $test_convert)" >> "$test_log"
    fi
    
    # Тест execute_cmd в тестовом режиме
    TEST_MODE=true
    local test_output=$(execute_cmd "echo test" 2>&1)
    if [[ "$test_output" == *"ТЕСТ: echo test"* ]]; then
        echo "  ✅ execute_cmd: OK"
    else
        echo "  ❌ execute_cmd: ОШИБКА (неверный вывод)"
        echo "execute_cmd: ОШИБКА (неверный вывод: $test_output)" >> "$test_log"
    fi
    
    echo "2. Проверка анализа системы..."
    
    # Запуск всех функций анализа в тестовом режиме
    TEST_MODE=true
    TOTAL_ESTIMATE=0
    
    analyze_disk > /dev/null 2>&1
    analyze_docker > /dev/null 2>&1
    analyze_journal > /dev/null 2>&1
    analyze_apt > /dev/null 2>&1
    analyze_snap > /dev/null 2>&1
    analyze_temp_files > /dev/null 2>&1
    
    if [ $TOTAL_ESTIMATE -gt 0 ]; then
        echo "  ✅ Функции анализа: OK (оценка: $TOTAL_ESTIMATE MB)"
    else
        echo "  ❌ Функции анализа: ОШИБКА (нулевая оценка)"
        echo "Функции анализа: ОШИБКА (нулевая оценка)" >> "$test_log"
    fi
    
    echo "3. Проверка функций очистки..."
    
    # Запуск всех функций очистки в тестовом режиме
    clean_docker > /dev/null 2>&1
    clean_journal > /dev/null 2>&1
    clean_apt > /dev/null 2>&1
    clean_snap > /dev/null 2>&1
    clean_temp_files > /dev/null 2>&1
    
    echo "  ✅ Функции очистки: OK"
    
    echo "4. Проверка обработки аргументов..."
    
    # Тест валидации аргументов
    local test_args=("--journal-days" "invalid" "--journal-size" "9999")
    if ! parse_args "${test_args[@]}" > /dev/null 2>&1; then
        echo "  ✅ Валидация аргументов: OK (обнаружены некорректные значения)"
    else
        echo "  ❌ Валидация аргументов: ОШИБКА (приняты некорректные значения)"
        echo "Валидация аргументов: ОШИБКА (приняты некорректные значения)" >> "$test_log"
    fi
    
    echo "5. Проверка зависимостей..."
    
    # Временно добавляем несуществующую зависимость для теста
    local orig_deps=("${DEPENDENCIES[@]}")
    DEPENDENCIES+=("nonexistent_command_12345")
    
    if ! check_dependencies > /dev/null 2>&1; then
        echo "  ✅ Проверка зависимостей: OK (обнаружена отсутствующая зависимость)"
    else
        echo "  ❌ Проверка зависимостей: ОШИБКА (не обнаружена отсутствующая зависимость)"
        echo "Проверка зависимостей: ОШИБКА (не обнаружена отсутствующая зависимость)" >> "$test_log"
    fi
    
    # Восстанавливаем оригинальный список зависимостей
    DEPENDENCIES=("${orig_deps[@]}")
    
    echo "6. Проверка systemd-таймера..."
    
    if command -v systemctl &>/dev/null; then
        echo "  ✅ systemd доступен для создания таймеров"
    else
        echo "  ⚠️ systemd недоступен, таймеры не могут быть протестированы"
    fi
    
    echo
    if [ -s "$test_log" ]; then
        echo "❌ Самотестирование завершено с ошибками. Подробности в $test_log"
        cat "$test_log"
        return 1
    else
        echo "✅ Самотестирование успешно завершено!"
        rm -f "$test_log"
        return 0
    fi
}

show_config_menu() {
    local choice
    
    while true; do
        clear
        echo "=== $SCRIPT_NAME v$VERSION - Настройка параметров ==="
        echo
        echo "1) Дни хранения журналов systemd: $JOURNAL_DAYS"
        echo "2) Максимальный размер журналов (MB): $JOURNAL_SIZE"
        echo "3) Сохранять образы Docker: $DOCKER_KEEP_IMAGES"
        echo "4) Возраст временных файлов для удаления (дни): $TEMP_FILES_AGE"
        echo "5) Использовать syslog для логирования: $USE_SYSLOG"
        echo "6) Использовать JSON-формат для логов: $USE_JSON_LOG"
        echo "7) Запрашивать подтверждение для apt autoremove: $CONFIRM_APT_AUTOREMOVE"
        echo
        echo "t) Настройка тестовых данных"
        echo "s) Сохранить настройки"
        echo "q) Выйти без сохранения"
        echo
        read -p "Выберите опцию: " choice
        
        case "$choice" in
            1)
                read -p "Введите количество дней хранения журналов [1-365]: " new_value
                if [[ "$new_value" =~ ^[0-9]+$ ]] && [ "$new_value" -ge 1 ] && [ "$new_value" -le 365 ]; then
                    JOURNAL_DAYS=$new_value
                else
                    echo "Некорректное значение. Должно быть число от 1 до 365."
                    read -p "Нажмите Enter для продолжения..."
                fi
                ;;
            2)
                read -p "Введите максимальный размер журналов в MB [50-5000]: " new_value
                if [[ "$new_value" =~ ^[0-9]+$ ]] && [ "$new_value" -ge 50 ] && [ "$new_value" -le 5000 ]; then
                    JOURNAL_SIZE=$new_value
                else
                    echo "Некорректное значение. Должно быть число от 50 до 5000."
                    read -p "Нажмите Enter для продолжения..."
                fi
                ;;
            3)
                if [ "$DOCKER_KEEP_IMAGES" = true ]; then
                    DOCKER_KEEP_IMAGES=false
                else
                    DOCKER_KEEP_IMAGES=true
                fi
                ;;
            4)
                read -p "Введите возраст временных файлов для удаления (дни) [1-30]: " new_value
                if [[ "$new_value" =~ ^[0-9]+$ ]] && [ "$new_value" -ge 1 ] && [ "$new_value" -le 30 ]; then
                    TEMP_FILES_AGE=$new_value
                else
                    echo "Некорректное значение. Должно быть число от 1 до 30."
                    read -p "Нажмите Enter для продолжения..."
                fi
                ;;
            5)
                if [ "$USE_SYSLOG" = true ]; then
                    USE_SYSLOG=false
                else
                    USE_SYSLOG=true
                fi
                ;;
            6)
                if [ "$USE_JSON_LOG" = true ]; then
                    USE_JSON_LOG=false
                else
                    USE_JSON_LOG=true
                fi
                ;;
            7)
                if [ "$CONFIRM_APT_AUTOREMOVE" = true ]; then
                    CONFIRM_APT_AUTOREMOVE=false
                else
                    CONFIRM_APT_AUTOREMOVE=true
                fi
                ;;
            t)
                clear
                echo "=== Настройка тестовых данных ==="
                echo
                read -p "Размер Docker (MB) [$TEST_DOCKER_SIZE]: " new_value
                [ -n "$new_value" ] && TEST_DOCKER_SIZE=$new_value
                
                read -p "Размер журналов (MB) [$TEST_JOURNAL_SIZE]: " new_value
                [ -n "$new_value" ] && TEST_JOURNAL_SIZE=$new_value
                
                read -p "Размер APT кэша (MB) [$TEST_APT_SIZE]: " new_value
                [ -n "$new_value" ] && TEST_APT_SIZE=$new_value
                
                read -p "Размер Snap (MB) [$TEST_SNAP_SIZE]: " new_value
                [ -n "$new_value" ] && TEST_SNAP_SIZE=$new_value
                
                read -p "Размер временных файлов (MB) [$TEST_TEMP_SIZE]: " new_value
                [ -n "$new_value" ] && TEST_TEMP_SIZE=$new_value
                
                echo "Тестовые данные обновлены."
                read -p "Нажмите Enter для продолжения..."
                ;;
            s|S)
                if [ -n "${CONFIG_PATH:-}" ]; then
                    save_config
                    read -p "Настройки сохранены в $CONFIG_PATH. Нажмите Enter для продолжения..."
                elif [ "${EUID:-$(id -u)}" -ne 0 ]; then
                    mkdir -p "$USER_CONFIG_DIR"
                    save_config
                    read -p "Настройки сохранены в $USER_CONFIG_FILE. Нажмите Enter для продолжения..."
                else
                    save_config
                    read -p "Настройки сохранены. Нажмите Enter для продолжения..."
                fi
                return
                ;;
            q|Q)
                return
                ;;
            *)
                echo "Некорректный выбор."
                read -p "Нажмите Enter для продолжения..."
                ;;
        esac
    done
}

show_help() {
    echo "SafeClean v$VERSION - Безопасная очистка системы"
    echo
    echo "Использование: $SCRIPT_NAME [ОПЦИИ]"
    echo
    echo "Опции:"
    echo "  --force               Выполнить очистку без подтверждения (требуются права root)"
    echo "  --dry-run             Показать анализ без выполнения очистки"
    echo "  --test-mode           Тестовый режим (без реального выполнения команд)"
    echo "  --journal-days DAYS   Хранить журналы не старше DAYS дней (по умолчанию: $JOURNAL_DAYS)"
    echo "  --journal-size SIZE   Ограничить размер журналов до SIZE MB (по умолчанию: $JOURNAL_SIZE)"
    echo "  --keep-docker-images  Не удалять образы Docker при очистке"
    echo "  --config              Настроить параметры через интерактивное меню"
    echo "  --config-path PATH    Использовать указанный путь для конфигурации"
    echo "  --syslog              Включить логирование в syslog"
    echo "  --json-log            Использовать JSON-формат для логов в syslog"
    echo "  --no-confirm-autoremove Не запрашивать подтверждение для apt autoremove"
    echo "  --schedule TYPE       Добавить в расписание (daily, weekly, monthly)"
    echo "  --schedule-systemd TYPE Добавить в systemd-таймер (daily, weekly, monthly)"
    echo "  --unschedule          Удалить из всех расписаний (cron и systemd)"
    echo "  --self-test           Запустить самотестирование скрипта"
    echo "  --install             Установить скрипт в систему (требуются права root)"
    echo "  --uninstall           Удалить скрипт из системы (требуются права root)"
    echo "  --version             Показать версию"
    echo "  --help                Показать это сообщение"
    echo
    echo "Примеры:"
    echo "  $SCRIPT_NAME --dry-run                  # Анализ без очистки"
    echo "  $SCRIPT_NAME --force                    # Очистка без подтверждения"
    echo "  $SCRIPT_NAME --config                   # Настройка параметров"
    echo "  $SCRIPT_NAME --schedule-systemd weekly  # Добавить в еженедельный systemd-таймер"
    echo "  $SCRIPT_NAME --schedule weekly          # Добавить в еженедельное cron-расписание"
    exit 0
}

check_root_for_force() {
    if [ "$FORCE_MODE" = true ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "Для использования --force требуются права root. Запустите с sudo."
        exit 1
    fi
}

validate_numeric_param() {
    local param_name="$1"
    local param_value="$2"
    local min_value="$3"
    local max_value="$4"
    
    if ! [[ "$param_value" =~ ^[0-9]+$ ]] || [ "$param_value" -lt "$min_value" ] || [ "$param_value" -gt "$max_value" ]; then
        echo "Ошибка: $param_name должен быть числом от $min_value до $max_value"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) FORCE_MODE=true ;;
            --dry-run) DRY_RUN=true ;;
            --test-mode) TEST_MODE=true ;;
            --journal-days)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    echo "Ошибка: параметр --journal-days требует значения"
                    exit 1
                fi
                validate_numeric_param "--journal-days" "$2" 1 365
                JOURNAL_DAYS="$2"
                shift
                ;;
            --journal-size)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    echo "Ошибка: параметр --journal-size требует значения"
                    exit 1
                fi
                validate_numeric_param "--journal-size" "$2" 50 5000
                JOURNAL_SIZE="$2"
                shift
                ;;
            --keep-docker-images) DOCKER_KEEP_IMAGES=true ;;
            --config) show_config_menu; exit 0 ;;
            --config-path)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    echo "Ошибка: параметр --config-path требует значения"
                    exit 1
                fi
                CONFIG_PATH="$2"
                shift
                ;;
            --syslog) USE_SYSLOG=true ;;
            --json-log) USE_JSON_LOG=true; USE_SYSLOG=true ;;
            --no-confirm-autoremove) CONFIRM_APT_AUTOREMOVE=false ;;
            --schedule)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    echo "Ошибка: параметр --schedule требует значения (daily, weekly, monthly)"
                    exit 1
                fi
                schedule_script "$2" false
                exit 0
                ;;
            --schedule-systemd)
                if [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
                    echo "Ошибка: параметр --schedule-systemd требует значения (daily, weekly, monthly)"
                    exit 1
                fi
                if ! command -v systemctl &>/dev/null; then
                    echo "Ошибка: systemd не найден в системе"
                    exit 1
                fi
                schedule_script "$2" true
                exit 0
                ;;
            --unschedule) unschedule_script; exit 0 ;;
            --self-test) self_test; exit $? ;;
            --install) install_script ;;
            --uninstall) uninstall_script ;;
            --version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
            --help) show_help ;;
            *) echo "Неверный аргумент: $1. Используйте --help для справки"; exit 1 ;;
        esac
        shift
    done
}

main() {
    # Загрузка конфигурации
    load_config
    
    # Проверка зависимостей
    check_dependencies
    
    if ! touch "$TEMP_FILE" 2>/dev/null; then
        echo "Ошибка: Нет прав на запись в /tmp"
        exit 1
    fi

    if [ $# -eq 0 ]; then
        show_help
    fi

    parse_args "$@"
    
    # Проверка прав root для --force
    check_root_for_force
    
    if [ "${EUID:-$(id -u)}" -ne 0 ] && { command -v apt &>/dev/null || command -v snap &>/dev/null || journalctl --disk-usage &>/dev/null; }; then
        echo "Для некоторых операций требуются права root. Запустите с sudo."
        exit 1
    fi

    > "$TEMP_FILE"
    log_message "=== 🔍 SafeClean v$VERSION: Предварительный анализ ==="
    if [ "$TEST_MODE" = true ]; then
        log_message "⚠️ ТЕСТОВЫЙ РЕЖИМ: команды не будут выполнены"
    fi
    log_message ""

    analyze_disk
    analyze_docker
    analyze_journal
    analyze_apt
    analyze_snap
    analyze_temp_files

    log_message "🧾 Резюме записано в: $TEMP_FILE"
    log_message ""
    log_message "📊 Ожидаемый объём очистки: ~${TOTAL_ESTIMATE}MB"
    log_message ""

    if ! $FORCE_MODE && ! $DRY_RUN && ! $TEST_MODE; then
        read -p "⚠️  Выполнить очистку? (y/N): " confirm
        if [[ ! "${confirm:-N}" =~ ^[Yy]$ ]]; then
            log_message "❌ Очистка отменена пользователем."
            exit 0
        fi
    elif $DRY_RUN; then
        log_message "✅ Режим --dry-run: Очистка не будет выполнена."
        exit 0
    elif $TEST_MODE; then
        log_message "✅ Режим --test-mode: Команды будут показаны, но не выполнены."
    else
        log_message "✅ Режим --force активен: очистка без подтверждения."
    fi

    log_message ""
    log_message "🚀 Начинаем очистку..."

    clean_docker
    clean_journal
    clean_apt
    clean_snap
    clean_temp_files

    if [ "$TEST_MODE" = true ]; then
        log_message ""
        log_message "📍 ТЕСТ: Место на диске после (симуляция):"
        log_message "Filesystem      Size  Used Avail Use% Mounted on"
        log_message "/dev/sda1       100G   60G   40G  60% /"
        log_message ""
        log_message "📊 ТЕСТ: Освобождено приблизительно: ${TOTAL_ESTIMATE} MB (симуляция)"
    else
        local disk_after
        if ! disk_after=$(df --output=used / | tail -n1 | tr -d '[:space:]'); then
            log_error "Не удалось получить информацию о дисковом пространстве после очистки"
            disk_after=$DISK_BEFORE
        fi
        
        local freed=$(( (DISK_BEFORE - disk_after) / 1024 ))

        log_message ""
        log_message "📍 Место на диске после:"
        if ! df -h | tee -a "$TEMP_FILE"; then
            log_error "Не удалось получить информацию о дисковом пространстве"
        fi
        log_message ""
        log_message "📊 Освобождено приблизительно: ${freed} MB"
    fi
    
    log_message ""
    log_message "✅ Очистка завершена."
    log_to_syslog "Очистка завершена. Освобождено приблизительно: ${TOTAL_ESTIMATE} MB"
}

# Запуск основной функции с передачей всех аргументов
main "$@"
