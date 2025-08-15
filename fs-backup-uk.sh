#!/bin/bash

# ==============================================================================
# Універсальний скрипт для резервного копіювання файлової системи
# Використовує rsync для створення повних, інкрементних копій та синхронізації.
# Враховує динамічне виключення теки з бекапами.
# Погоджує детальний план операцій з користувачем.
# Виконує аналіз дискового простору.
# Оптимізована та спрощена версія з єдиною логікою та попередніми перевірками.
# Використовує ACL-записи у цифровому форматі.
# Після сінхронізації резервна копія перейменовується на поточну дату.
# (c) 2025, Gemini 2.5 pro (Google)
# (c) 2025, Serhii Horichenko
# ==============================================================================

# Безпечний режим: виходити при помилці, при використанні невизначеної змінної
# та повертати помилку, якщо команда в конвеєрі (|) завершилась невдало.
set -eo pipefail

# --- КОНФІГУРАЦІЯ ТА ТИПОВІ ЗНАЧЕННЯ ---

# Типові значення
MODE=""
SOURCE_PATH="/"
DEST_PATH="."
RECOVER_DATE=""
FORCE_EXECUTION=false

# Поточні дата та час
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_TIME=$(date +%H%M%S)

# Кольори для виводу
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'

# Список виключень для rsync. Важливо виключити віртуальні ФС та сам каталог з резервними копіями.
EXCLUDE_LIST=(
  "/dev/*"
  "/proc/*"
  "/sys/*"
  "/tmp/*"
  "/run/*"
  "/mnt/*"
  "/media/*"
  "/lost+found"
#  "*~"
# "*.bak"
#  "*/.cache"
#  "*/Cache"
)

# --- ФУНКЦІЇ ---

# Функція для виводу довідки
usage() {
  echo "Використання: $0 [режим] [опції]"
  echo
  echo "  РЕЖИМИ РОБОТИ (оберіть один):"
  echo "    --full, -f         Створити нову повну резервну копію."
  echo "    --sync, -s         Синхронізувати з останньою повною копією (оновити її)."
  echo "    --inc, -i          Створити інкрементну копію відносно останньої повної."
  echo "    --recover, -r      Відновити систему з копії за вказану дату (YYYY-MM-DD)."
  echo
  echo "  ОБОВ'ЯЗКОВІ ПАРАМЕТРИ:"
  echo "    Для --recover:     <дата у форматі YYYY-MM-DD>"
  echo
  echo "  ДОДАТКОВІ ОПЦІЇ:"
  echo "    --source <шлях>    Вказати джерело копіювання (типово: /)."
  echo "    --dest <шлях>      Вказати теку призначення для бекапів (типово: поточна тека)."
  echo "    --force, -y        Запустити без запиту на підтвердження."
  echo "    --help, -h         Показати цю довідку."
  echo
  exit 1
}

# Функція підтвердження плану виконання
plan_and_confirm() {
    local summary="$1"
    echo -e "${COLOR_YELLOW}--- ПЛАН ВИКОНАННЯ ---${COLOR_RESET}"
    echo -e "${summary}"
    echo -e "${COLOR_YELLOW}----------------------${COLOR_RESET}"

    # Перевірка, чи запускати план без погодження
    if [ "$FORCE_EXECUTION" = true ]; then
        echo -e "${COLOR_CYAN}Використано ключ --force або -y, запускаю виконання.${COLOR_RESET}"
        return 0
    fi

    # Запит підтвердження
    read -p "Ви погоджуєтеся на виконання цього плану? [y/N]: " response
    case "$response" in
        [yY][eE][sS] | [yY] | [jJ] | [jJ][aA] | [тТ][аА][кК] | [тТ])
            echo -e "\n${COLOR_GREEN}План підтверджено. Розпочинаю виконання...${COLOR_RESET}"
            return 0
            ;;
        *)
            echo -e "\n${COLOR_BLUE}Операцію скасовано користувачем.${COLOR_RESET}"
            exit 1
            ;;
    esac
}

# Генерація скрипту відновлення
generate_recovery_script() {
  local backup_path="$1"
  local recovery_script_path="${backup_path}/recovery.sh"

  # Створюємо сам скрипт recovery.sh
  cat > "$recovery_script_path" <<EOF
#!/bin/bash
# ВАЖЛИВО! Цей скрипт призначений для відновлення системи.
# Запускайте його з Live-CD/USB середовища з правами sudo.
# НЕ ЗАПУСКАЙТЕ НА ПРАЦЮЮЧІЙ СИСТЕМІ!

set -e

echo "!!! УВАГА: ПОЧИНАЄТЬСЯ ПРОЦЕС ВІДНОВЛЕННЯ СИСТЕМИ !!!"
echo "Переконайтесь, що ви запустили цей скрипт з Live-CD/USB."
read -p "Натисніть Enter для продовження або Ctrl+C для скасування..."

# Шлях до кореня нової системи (куди монтовано розділ)
RECOVERY_TARGET="/"

# Каталог, звідки відновлюємо (де лежить цей скрипт)
RECOVERY_SOURCE=\$(dirname "\$0")

echo "Джерело: \$RECOVERY_SOURCE"
echo "Призначення: \$RECOVERY_TARGET"

# Команда rsync для відновлення.
# --delete видалить у призначенні файли, яких немає в бекапі.
# Ключ -L (--copy-links) потрібен, щоби rsync копіював файли, на які вказують
# символічні посилання, а не створював самі посилання у відновленій системі.
rsync -aAXvL --progress --delete \\
      --exclude="/recovery.sh" \\
      --exclude="/skip-files.txt" \\
      "\$RECOVERY_SOURCE/" "\$RECOVERY_TARGET"

echo "✅ Відновлення завершено. Створіть вручну системні каталоги:"
echo "mkdir -p /dev /proc /sys /tmp /run /mnt /media"
echo "Після цього потрібно перевстановити завантажувач (GRUB)."
EOF

  chmod +x "$recovery_script_path"
}


# --- ОБРОБКА АРГУМЕНТІВ КОМАНДНОГО РЯДКА ---
if [ $# -eq 0 ]; then usage; fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f | --full) MODE="full" ;;
    -s | --sync) MODE="sync" ;;
    -i | --inc) MODE="inc" ;;
    -r | --recover)
      MODE="recover"
      if [ -n "$2" ]; then
          RECOVER_DATE="$2"
          shift
      else
          echo "Помилка: для --recover потрібно вказати дату YYYY-MM-DD." >&2
          exit 1
      fi
      ;;
    --source)
      if [ -n "$2" ]; then
          SOURCE_PATH="$2"
          shift
      else
          echo "Помилка: для --source потрібно вказати шлях." >&2
          exit 1
      fi
      ;;
    --dest)
      if [ -n "$2" ]; then
          DEST_PATH="$2"
          shift
      else
          echo "Помилка: для --dest потрібно вказати шлях." >&2
          exit 1
      fi
      ;;
    -y | --force) FORCE_EXECUTION=true ;;
    -h | --help) usage ;;
    *)
      echo "Невідомий параметр: $1" >&2
      usage
      ;;
  esac
  shift
done

# --- ПОПЕРЕДНІ ПЕРЕВІРКИ ---
# Перевірка наявності потрібних програм
for cmd in rsync numfmt; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${COLOR_RED}Помилка: необхідна програма '$cmd' відсутня. Будь ласка, встановіть її.${COLOR_RESET}"
        exit 1
    fi
done

# Перевірка наявності та доступності шляхів
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${COLOR_RED}Помилка: каталог-джерело '$SOURCE_PATH' не знайдено.${COLOR_RESET}"
    exit 1
fi
if [ ! -d "$DEST_PATH" ] || [ ! -w "$DEST_PATH" ]; then
    echo -e "${COLOR_RED}Помилка: каталог призначення '$DEST_PATH' не існує або недоступний для запису.${COLOR_RESET}"
    exit 1
fi

# Створюємо масив параметрів --exclude для rsync
RSYNC_EXCLUDES=()
for item in "${EXCLUDE_LIST[@]}"; do
    RSYNC_EXCLUDES+=(--exclude="$item")
done

# Додаємо виключення для самої теки з бекапами
ABSOLUTE_DEST_PATH=$(realpath "$DEST_PATH")
RSYNC_EXCLUDES+=(--exclude="${ABSOLUTE_DEST_PATH}/*")

# Змінна для зберігання плану
OPERATION_SUMMARY=""

# --- ОСНОВНА ЛОГІКА ---

# Режим: Повна копія
if [ "$MODE" = "full" ]; then
    TARGET_DIR="${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-full"

    # АНАЛІЗ МІСЦЯ
    echo "Аналіз дискового простору для повної копії..."
    REQUIRED_KB=$(df --total --block-size=1K --output=used "$SOURCE_PATH" | tail -n 1 | tr -d '[:space:]')
    AVAILABLE_KB=$(df --block-size=1K --output=avail "$DEST_PATH" | tail -n 1 | tr -d '[:space:]')
    REQUIRED_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" $((REQUIRED_KB * 1024)))
    AVAILABLE_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" $((AVAILABLE_KB * 1024)))

    # Формування плану
    OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Режим:${COLOR_RESET} Повна резервна копія\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Джерело:${COLOR_RESET} $SOURCE_PATH\nПризначення:${COLOR_RESET} $TARGET_DIR\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_YELLOW}Необхідно місця (оцінка):${COLOR_RESET} $REQUIRED_HUMAN\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_GREEN}Доступно на диску призначення:${COLOR_RESET} $AVAILABLE_HUMAN")

    # Перевірка, чи вистачає місця
    if (( REQUIRED_KB > AVAILABLE_KB )); then
        OPERATION_SUMMARY+=$(printf "%s" "\n\n${COLOR_RED}!!! УВАГА !!!\nНа диску призначення недостатньо вільного місця!${COLOR_RESET}")
        echo -e "$OPERATION_SUMMARY"
        exit 1
    fi

    plan_and_confirm "$OPERATION_SUMMARY"

    echo -e "\n${COLOR_GREEN}Створення повної копії до теки ${TARGET_DIR}...${COLOR_RESET}"
    mkdir -p "$TARGET_DIR"
    sudo rsync -aAXHv --progress --numeric-ids "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${TARGET_DIR}"
    generate_recovery_script "$TARGET_DIR"
    echo -e "\n${COLOR_GREEN}✅ Повна копія успішно створена в ${TARGET_DIR} ${COLOR_RESET}"

# Режим: Синхронізація
elif [ "$MODE" = "sync" ]; then
    LATEST_FULL=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-full" | sort -r | head -n 1)
    if [ -z "$LATEST_FULL" ]; then echo -e "${COLOR_RED}Помилка: не знайдено повної копії для синхронізації.${COLOR_RESET}" >&2; exit 1; fi
    OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Режим:${COLOR_RESET} Синхронізація\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Джерело:${COLOR_RESET} $SOURCE_PATH\n${COLOR_CYAN}Синхронізація з:${COLOR_RESET} $LATEST_FULL\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_YELLOW}Файли, видалені з джерела, будуть видалені також з резервної копії.${COLOR_RESET}")

    if [ ! -d "${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-full" ]; then
        NEW_BACKUP_NAME="${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-full"
        OPERATION_SUMMARY+=$(printf "%s" "\n${COLOR_YELLOW}Резервну копію буде перейменовано на: ${COLOR_RESET} $NEW_BACKUP_NAME\n")
    fi

    plan_and_confirm "$OPERATION_SUMMARY"

    echo -e "\n${COLOR_GREEN}Синхронізація з ${LATEST_FULL}...${COLOR_RESET}"
    # Видалення старих файлів
    sudo rsync -aAXH --delete --progress --numeric-ids --ignore-existing "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${LATEST_FULL}" | grep '^deleting '
    # Копіювання нових файлів
    sudo rsync -aAXHv --delete --progress --numeric-ids "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${LATEST_FULL}"
    generate_recovery_script "$LATEST_FULL"

    echo -e "\n${COLOR_GREEN}✅ Синхронізацію з ${LATEST_FULL} завершено.${COLOR_RESET}"
    if [ ! -d "${NEW_BACKUP_NAME}" ] && [ ! -z "$NEW_BACKUP_NAME" ]; then
        sudo mv -f "${LATEST_FULL}" "${NEW_BACKUP_NAME}"
        echo -e "\n${COLOR_YELLOW}Резервну копію перейменовано на: ${COLOR_RESET} $NEW_BACKUP_NAME\n"
    fi

# Режим: Інкрементна копія
elif [ "$MODE" = "inc" ]; then
    LATEST_FULL=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-full" | sort -r | head -n 1)
    if [ -z "$LATEST_FULL" ]; then echo -e "${COLOR_RED}Помилка: не знайдено базової копії для створення інкременту.${COLOR_RESET}" >&2; exit 1; fi
    TARGET_DIR="${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-inc-${CURRENT_TIME}"

    OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Режим:${COLOR_RESET} Інкрементна резервна копія\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Спосіб:${COLOR_RESET} Hard-links (економія місця, швидке виконання)\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Джерело:${COLOR_RESET} $SOURCE_PATH\n${COLOR_CYAN}Базова копія:${COLOR_RESET} $LATEST_FULL\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Зміни будуть збережені до теки:${COLOR_RESET} $TARGET_DIR")

    plan_and_confirm "$OPERATION_SUMMARY"

    echo -e "\n${COLOR_GREEN}Створення інкрементної копії до теки ${TARGET_DIR}...${COLOR_RESET}"
    sudo rsync -aAXv --progress --numeric-ids --link-dest="${LATEST_FULL}" "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${TARGET_DIR}"

  # Створення списку файлів, які були видалені в джерелі
  echo -e "\n${COLOR_YELLOW}Складання списку видалених файлів ${COLOR_RESET}(skip-files.txt)..."
  sudo rsync -aAXn --progress --delete "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${LATEST_FULL}" | \
    grep '^deleting ' | sed 's/^deleting //' > "${TARGET_DIR}/skip-files.txt"

  # Генерація скрипту відновлення для інкременту (складніша логіка)
  RECOVERY_SCRIPT_PATH="${TARGET_DIR}/recovery.sh"
  cat > "$RECOVERY_SCRIPT_PATH" <<EOF
#!/bin/bash
echo "!!! УВАГА: ВІДНОВЛЕННЯ З ІНКРЕМЕНТНОЇ КОПІЇ !!!"
echo "Цей процес відновить спочатку повну копію, а потім застосує зміни."
read -p "Натисніть Enter для продовження або Ctrl+C для скасування..."

RECOVERY_TARGET="/"
INC_BACKUP_DIR=\$(dirname "\$0")
FULL_BACKUP_DIR="${LATEST_FULL}" # Шлях до повної копії жорстко прописаний

# Крок 1: Відновлення з повної копії
echo "-> Крок 1/3: Відновлення з базової повної копії..."
sudo rsync -aAXv --delete --progress --numeric-ids "\${FULL_BACKUP_DIR}/" "\${RECOVERY_TARGET}"

# Крок 2: Відновлення змінених файлів з інкрементної копії
echo "-> Крок 2/3: Застосування змін з інкрементної копії..."
sudo rsync -aAXv --progress --numeric-ids "\${INC_BACKUP_DIR}/" "\${RECOVERY_TARGET}"

# Крок 3: Видалення файлів, перерахованих у skip-files.txt
if [ -f "\${INC_BACKUP_DIR}/skip-files.txt" ]; then
  echo "-> Крок 3/3: Видалення файлів, що відсутні в джерелі..."
  while IFS= read -r file_to_delete; do
    # Перевіряємо, чи існує файл перед видаленням
    if [ -e "\${RECOVERY_TARGET}\${file_to_delete}" ]; then
      echo "Видалення: \${RECOVERY_TARGET}\${file_to_delete}"
      sudo rm -rf "\${RECOVERY_TARGET}\${file_to_delete}"
    fi
  done < "\${INC_BACKUP_DIR}/skip-files.txt"
fi

echo "✅ Відновлення завершено."
EOF

  chmod +x "$RECOVERY_SCRIPT_PATH"
  echo -e "\n${COLOR_GREEN}✅ Інкрементна копія створена в ${TARGET_DIR} ${COLOR_RESET}"

# Режим: Відновлення
elif [ "$MODE" = "recover" ]; then
  LATEST_FULL=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-full" -newermt "${RECOVER_DATE} 00:00:00" ! -newermt "${RECOVER_DATE} 23:59:59" -o -newermt "1970-01-01" ! -newermt "${RECOVER_DATE}" | sort -r | head -n 1)

  if [ -z "$LATEST_FULL" ]; then
    echo -e "\n${COLOR_RED}Помилка: не знайдено відповідної повної копії для відновлення на дату ${COLOR_RESET} ${RECOVER_DATE}." >&2
    exit 1
  fi

  INCREMENTALS_TO_APPLY=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-inc-*" -newermt "$(stat -c %y "$LATEST_FULL")" -and ! -newermt "${RECOVER_DATE} 23:59:59" | sort)

  OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Режим:${COLOR_RESET} Відновлення системи\n")
  OPERATION_SUMMARY=$(printf "%s" "${COLOR_BLUE}Цільова дата:${COLOR_RESET}  ${RECOVER_DATE}")
  OPERATION_SUMMARY=$(printf "%s" "${COLOR_BLUE}Базова копія:${COLOR_RESET}   ${LATEST_FULL}")
  if [ -n "$INCREMENTALS_TO_APPLY" ]; then
      OPERATION_SUMMARY=$(printf "%s" "${COLOR_YELLOW}Інкременти для застосування:${COLOR_RESET}")
      OPERATION_SUMMARY=$(printf "%s" "${COLOR_YELLOW}${INCREMENTALS_TO_APPLY}${COLOR_RESET}")
  else
      OPERATION_SUMMARY=$(printf "%s" "${COLOR_YELLOW}Інкрементні копії не знайдені, буде відновлено лише повну копію.${COLOR_RESET}")
  fi
  OPERATION_SUMMARY+=$(printf "%s" "${COLOR_RED}Призначення:${COLOR_RESET} $SOURCE_PATH\n${COLOR_CYAN}Відновлення до: ${COLOR_RESET} $RECOVER_DATE\n")
  OPERATION_SUMMARY+=$(printf "%s" "\n${COLOR_RED}!!! УВАГА: ЦЯ ОПЕРАЦІЯ ПЕРЕЗАПИШЕ ДАНІ В: \n${SOURCE_PATH} !!!\n${COLOR_RESET}\n")

  plan_and_confirm "$OPERATION_SUMMARY"

  echo -e "\n${COLOR_GREEN}Відновлення до ${RECOVER_DATE}...${COLOR_RESET}"

  # Крок 1: Відновлення з повної копії
  echo -e "\n${COLOR_YELLOW}-> Крок 1: Відновлення з базової повної копії ${LATEST_FULL}...${COLOR_RESET}"
  sudo rsync -aAXv --delete --progress --numeric-ids --exclude="/recovery.sh" "${LATEST_FULL}/" "${SOURCE_PATH}"

  # Крок 2: Послідовне застосування інкрементів
  if [ -n "$INCREMENTALS_TO_APPLY" ]; then
    step=2
    for inc_dir in $INCREMENTALS_TO_APPLY; do
      echo -e "\n${COLOR_YELLOW}->  Крок ${step}: Застосування інкременту ${inc_dir}... ${COLOR_RESET}"
      # Копіюємо змінені/нові файли
      sudo rsync -aAXv --progress --numeric-ids "${inc_dir}/" "${SOURCE_PATH}"
      # Видаляємо файли зі списку skip-files.txt
      if [ -f "${inc_dir}/skip-files.txt" ]; then
        while IFS= read -r file_to_delete; do
          if [ -e "${SOURCE_PATH}${file_to_delete}" ]; then
            sudo rm -rf "${SOURCE_PATH}${file_to_delete}"
          fi
        done < "${inc_dir}/skip-files.txt"
      fi
      ((step++))
    done
  fi
  echo -e "\n${COLOR_GREEN}✅ Відновлення до $SOURCE_PATH на дату ${RECOVER_DATE} завершено. ${COLOR_RESET}"


else
  echo -e "\n${COLOR_RED}Помилка: не вказано режим роботи.\n ${COLOR_RESET}" >&2
  usage
fi

echo -e "\n${COLOR_GREEN}Операцію успішно завершено.\n${COLOR_RESET}"

