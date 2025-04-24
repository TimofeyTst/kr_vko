#!/bin/bash

# Проверка условий запуска
[[ $EUID -eq 0 ]] && { echo "Запуск от root запрещен!"; exit 1; }
[[ "$(uname)" != "Linux" ]] && { echo "Скрипт поддерживается только в Linux!"; exit 1; }
[[ -z "$BASH_VERSION" ]] && { echo "Скрипт должен выполняться в Bash!"; exit 1; }

ROOT_DIR=$(dirname "$(realpath "$0")")
DB_PATH="$ROOT_DIR/db/vkr.db"

MESSAGES_DIR="$ROOT_DIR/messages"
DETECTIONS_DIR="$MESSAGES_DIR/detections"
SHOOTING_DIR="$MESSAGES_DIR/shooting"
AMMO_DIR="$MESSAGES_DIR/ammo"
CHECK_DIR="$MESSAGES_DIR/check"

# Определяем папку для логов
KP_LOG_PATH="$ROOT_DIR/logs/kp.log"
>"$KP_LOG_PATH" # Очистка файла при запуске

# Создание необходимых директорий
mkdir -p "$MESSAGES_DIR" "$DETECTIONS_DIR" "$SHOOTING_DIR" "$AMMO_DIR" "$CHECK_DIR" &>/dev/null

# Создание базы данных и таблиц, если они не существуют
init_database() {
	if [[ -f "$DB_PATH" ]]; then
		echo "Database already exist, delete it"
		rm -f "$DB_PATH"
	fi

	sqlite3 "$DB_PATH" <<EOF
    CREATE TABLE IF NOT EXISTS targets (
        id TEXT PRIMARY KEY,
        speed REAL,
        ttype TEXT,
        direction BOOLEAN
    );

    CREATE TABLE IF NOT EXISTS systems (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE
    );

	CREATE TABLE IF NOT EXISTS ammo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        system_id INTEGER,
		count INTEGER,
        timestamp TEXT,
		FOREIGN KEY (system_id) REFERENCES systems (id)
    );

    CREATE TABLE IF NOT EXISTS detections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_id TEXT,
        system_id INTEGER,
		x INTEGER,
		y INTEGER,
        timestamp TEXT,
        FOREIGN KEY (target_id) REFERENCES targets (id),
        FOREIGN KEY (system_id) REFERENCES systems (id)
    );

    CREATE TABLE IF NOT EXISTS shooting (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        target_id TEXT,
        system_id INTEGER,
        timestamp TEXT,
		result BOOLEAN,
		result_timestamp TEXT,
        FOREIGN KEY (target_id) REFERENCES targets (id),
        FOREIGN KEY (system_id) REFERENCES systems (id)
    );
EOF
}

# Расшифровка и проверка сообщения
verify_and_decrypt() {
    local file="$1"
    local checksum=$(head -n1 "$file" | cut -d' ' -f1)
    local encoded=$(cut -d' ' -f2- "$file")
    local decoded=$(echo -n "$encoded" | base64 -d)
    local actual_checksum=$(echo -n "$decoded" | sha256sum | cut -d' ' -f1)

    if [[ "$checksum" == "$actual_checksum" ]]; then
        echo "$decoded"
    else
		echo "ALARM: нарушение целостности файла!" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') ALARM: нарушение целостности файла $file" >>"$KP_LOG_PATH"
        return 1
    fi
}

# Получение system_id по имени (добавляет в базу, если ее нет)
upsert_system_id() {
    local name="$1"
    local id
    id=$(sqlite3 "$DB_PATH" "SELECT id FROM systems WHERE name='$name';")

    if [[ -z "$id" ]]; then
        sqlite3 "$DB_PATH" "INSERT INTO systems (name) VALUES ('$name');"
        id=$(sqlite3 "$DB_PATH" "SELECT id FROM systems WHERE name='$name';")
    fi
    echo "$id"
}

# Обработка обнаружений (расшифрованные данные)
handle_detection() {
    local msg="$1" file="$2"
    read -r ts time system_id target_id x_line y_line speed target_type <<<"$msg"
    local x=${x_line#*:}
    local y=${y_line#*:}
    local dir="NULL"

	echo "$ts $time $system_id $target_id $x $y $speed $target_type"

	if [[ "$target_type" == "ББ БР-1" ]]; then
		dir=1;
		target_type="ББ БР"
    	echo "$ts $time $system_id Обнаружена цель ID:$target_id X:$x Y:$y V:$speed м/с $target_type" >>"$KP_LOG_PATH"
		echo "$ts $time $system_id Цель ID:$target_id движется к СПРО" >>"$KP_LOG_PATH"
	else
    	echo "$ts $time $system_id Обнаружена цель ID:$target_id X:$x Y:$y V:$speed м/с $target_type" >>"$KP_LOG_PATH"
	fi

    sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO targets (id, speed, ttype, direction) VALUES ('$target_id', $speed, '$target_type', $dir);"

    local sys_id=$(upsert_system_id "$system_id")
	sqlite3 "$DB_PATH" "INSERT INTO detections (target_id, system_id, x, y, timestamp) VALUES ('$target_id', $sys_id, $x, $y, '$timestamp');"

	rm -f "$file"
}

# Обработка файла стрельбы
handle_shooting() {
    local msg="$1" file="$2"
    read -r ts time system_id target_id result_ts result_time result <<<"$msg"

	echo "$ts $time $system_id $target_id $result_ts $result_time $result"

    local sys_id=$(upsert_system_id "$system_id")
    if [[ -z "$result_ts" ]]; then
        sqlite3 "$DB_PATH" "INSERT INTO shooting (target_id, system_id, timestamp) VALUES ('$target_id', $sys_id, '$ts $time');"
        ((ammo[$system_id]--))
        echo "$ts $time $system_id Выстрел по ID:$target_id. Боезапас: ${ammo[$system_id]}" >>"$KP_LOG_PATH"
    else
        local last_id=$(sqlite3 "$DB_PATH" "SELECT id FROM shooting WHERE target_id='$target_id' AND system_id=$sys_id AND timestamp='$ts $time' ORDER BY id DESC LIMIT 1;")
        sqlite3 "$DB_PATH" "UPDATE shooting SET result=$result, result_timestamp='$result_ts $result_time' WHERE id=$last_id;"
        echo "$ts $time $system_id $([[ $result == 1 ]] && echo 'Уничтожена цель' || echo 'Промах') по ID:$target_id при выстреле в $result_ts $result_time " >>"$KP_LOG_PATH"
    fi

    rm -f "$file"
}

declare -A ammo

# Пополение боекомплекта
handle_ammo() {
    local msg="$1" file="$2"
    read -r ts time system_id count <<<"$msg"
    
	ammo["$system_id"]=$count

	echo "$ts $time $system_id $count"
	echo "$ts $time $system_id Боезапас обновлен. Загружено $count снарядов" >>"$KP_LOG_PATH"

	local sys_id=$(upsert_system_id "$system_id")
    sqlite3 "$DB_PATH" "INSERT INTO ammo (system_id, count, timestamp) VALUES ($sys_id, $count, '$ts $time');"

    rm -f "$file"
}

declare -A systems_map=(
	["zrdn1"]="ЗРДН1"
	["zrdn2"]="ЗРДН2"
	["zrdn3"]="ЗРДН3"
	["spro"]="СПРО"
	["rls1"]="РЛС1"
	["rls2"]="РЛС2"
	["rls3"]="РЛС3"
)

declare -A system_status

for key in "${!systems_map[@]}"; do
	system_status["$key"]=1 # 1 - работает
done

health_check() {
	while true; do
		for key in "${!systems_map[@]}"; do
			if [[ ! -f "$CHECK_DIR/ping_$key" ]]; then
                # echo "PING $key" # TODO: think about
				touch "$CHECK_DIR/ping_$key"
			fi
		done

		sleep 30

		for key in "${!systems_map[@]}"; do
			if [[ -f "$CHECK_DIR/ping_$key" ]]; then
				# Если система впервые перестала работать, выводим сообщение
				if [[ ${system_status[$key]} -eq 1 ]]; then
					check_time=$(date '+%d-%m %H:%M:%S.%3N')
					echo "$check_time ${system_names[$key]} is NOT AVAILABLE"
					echo "$check_time ${system_names[$key]} is NOT AVAILABLE" >>"$KP_LOG_PATH"
					system_status["$key"]=0 # Отмечаем как неработающую
				fi
			else
				# Если система была неработающей, но теперь отвечает, выводим сообщение о восстановлении
				if [[ ${system_status[$key]} -eq 0 ]]; then
					check_time=$(date '+%d-%m %H:%M:%S.%3N')
					echo "$check_time ${system_names[$key]} is AVAILABLE"
					echo "$check_time ${system_names[$key]} is AVAILABLE" >>"$KP_LOG_PATH"
					system_status["$key"]=1 # Отмечаем как работающую
				fi
			fi
			rm -f "$CHECK_DIR/pong_$key"
		done

		sleep 30
	done
}

init_database
health_check &

echo "Мониторинг файлов в $DETECTIONS_DIR, $SHOOTING_DIR и $AMMO_DIR"
while true; do
	mapfile -t recent_files < <(find "$DETECTIONS_DIR" "$SHOOTING_DIR" "$AMMO_DIR" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -n 10 | cut -d' ' -f2-)

	for file in "${recent_files[@]}"; do
		decrypted_message=$(verify_and_decrypt "$file") || continue

		if [[ "$file" == "$DETECTIONS_DIR/"* ]]; then
			handle_detection "$decrypted_message" "$file"
		elif [[ "$file" == "$SHOOTING_DIR/"* ]]; then
			handle_shooting "$decrypted_message" "$file"
		elif [[ "$file" == "$AMMO_DIR/"* ]]; then
			handle_ammo "$decrypted_message" "$file"
		fi
	done
	sleep 0.01
done