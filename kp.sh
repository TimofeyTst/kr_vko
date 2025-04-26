#!/bin/bash

source utils/const.sh

# Проверка условий запуска
[[ $EUID -eq 0 ]] && { echo "Запуск от root запрещен!"; exit 1; }
[[ "$(uname)" != "Linux" ]] && { echo "Скрипт поддерживается только в Linux!"; exit 1; }
[[ -z "$BASH_VERSION" ]] && { echo "Скрипт должен выполняться в Bash!"; exit 1; }

ROOT_DIR=$(dirname "$(realpath "$0")")
DB_PATH="$ROOT_DIR/db/vkr.db"

# Определяем папку для логов
KP_LOG_PATH="$ROOT_DIR/logs/kp.log"
>"$KP_LOG_PATH" # Очистка файла при запуске

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
		target_type TEXT,
		is_move_to_spro BOOLEAN,
		create_ts TEXT DEFAULT (datetime('now')),
		update_ts TEXT DEFAULT (datetime('now'))
	);

	CREATE TABLE IF NOT EXISTS services (
		id TEXT PRIMARY KEY,
		create_ts TEXT DEFAULT (datetime('now')),
		update_ts TEXT DEFAULT (datetime('now'))
	);

	CREATE TABLE IF NOT EXISTS ammo (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		service_id TEXT NOT NULL,
		count INTEGER,
		timestamp TEXT,
		create_ts TEXT DEFAULT (datetime('now')),
		update_ts TEXT DEFAULT (datetime('now')),
		FOREIGN KEY (service_id) REFERENCES services(id)
	);

	CREATE TABLE IF NOT EXISTS detections (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		target_id TEXT NOT NULL,
		service_id TEXT NOT NULL,
		x INTEGER NOT NULL,
		y INTEGER NOT NULL,
		timestamp TEXT NOT NULL,
		create_ts TEXT DEFAULT (datetime('now')),
		update_ts TEXT DEFAULT (datetime('now')),
		FOREIGN KEY (target_id) REFERENCES targets(id),
		FOREIGN KEY (service_id) REFERENCES services(id)
	);

	CREATE TABLE IF NOT EXISTS shots (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		target_id TEXT NOT NULL,
		service_id TEXT NOT NULL,
		timestamp TEXT NOT NULL, -- момент выстрела
		is_hit_target BOOLEAN,          -- NULL, 0 или 1
		hit_target_ts TEXT,   -- время попадания/промаха
		create_ts TEXT DEFAULT (datetime('now')),
		update_ts TEXT DEFAULT (datetime('now')),
		FOREIGN KEY (target_id) REFERENCES targets(id),
		FOREIGN KEY (service_id) REFERENCES services(id)
	);

	CREATE TRIGGER IF NOT EXISTS trg_targets_update
	AFTER UPDATE ON targets
	FOR EACH ROW
	BEGIN
		UPDATE targets SET update_ts = datetime('now') WHERE id = OLD.id;
	END;

	CREATE TRIGGER IF NOT EXISTS trg_services_update
	AFTER UPDATE ON services
	FOR EACH ROW
	BEGIN
		UPDATE services SET update_ts = datetime('now') WHERE id = OLD.id;
	END;

	CREATE TRIGGER IF NOT EXISTS trg_ammo_update
	AFTER UPDATE ON ammo
	FOR EACH ROW
	BEGIN
		UPDATE ammo SET update_ts = datetime('now') WHERE id = OLD.id;
	END;

	CREATE TRIGGER IF NOT EXISTS trg_detections_update
	AFTER UPDATE ON detections
	FOR EACH ROW
	BEGIN
		UPDATE detections SET update_ts = datetime('now') WHERE id = OLD.id;
	END;

	CREATE TRIGGER IF NOT EXISTS trg_shots_update
	AFTER UPDATE ON shots
	FOR EACH ROW
	BEGIN
		UPDATE shots SET update_ts = datetime('now') WHERE id = OLD.id;
	END;

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

# Получение service_id по имени (добавляет в базу, если ее нет)
upsert_service_id() {
    local service_id="$1"

    sqlite3 "$DB_PATH" "INSERT INTO services (id) VALUES ('$service_id') ON CONFLICT(id) DO UPDATE SET update_ts = datetime('now');"

    echo "$service_id"
}

# Обработка обнаружений (расшифрованные данные)
handle_detect() {
    local msg="$1" file="$2"
    read -r ts time service_id target_id x_line y_line speed target_type <<<"$msg"
    local x=${x_line#*:}
    local y=${y_line#*:}
    local dir="NULL"

	echo -e "$ts $time\t$service_id\tDETECT\t$target_id\t$x $y $speed\t$target_type"

	if [[ "$target_type" == "ББ БР->СПРО" ]]; then
		dir=1;
		target_type="ББ БР"
    	echo -e "$ts $time\t$service_id\tОбнаружена цель ID:$target_id\tX:$x\tY:$y\tV:$speed м/с\t$target_type движется к СПРО" >>"$KP_LOG_PATH"
    	# echo -e "$ts $time\t$service_id\tОбнаружена цель ID:$target_id\tX:$x\tY:$y\tV:$speed м/с\t$target_type движется к СПРО"
	else
    	echo -e "$ts $time\t$service_id\tОбнаружена цель ID:$target_id\tX:$x\tY:$y\tV:$speed м/с\t$target_type" >>"$KP_LOG_PATH"
    	# echo -e "$ts $time\t$service_id\tОбнаружена цель ID:$target_id\tX:$x\tY:$y\tV:$speed м/с\t$target_type"
	fi

    sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO targets (id, speed, target_type, is_move_to_spro) VALUES ('$target_id', $speed, '$target_type', $dir);"

    local serv_id=$(upsert_service_id "$service_id")
	sqlite3 "$DB_PATH" "INSERT INTO detections (target_id, service_id, x, y, timestamp) VALUES ('$target_id', '$serv_id', $x, $y, '$timestamp');"

	rm -f "$file"
}

# Обработка файла стрельбы
handle_shot() {
    local msg="$1" file="$2"
    read -r ts time service_id target_id result_ts result_time is_hit_target <<<"$msg"

	echo -e "$ts $time\t$service_id\tSHOT\t$target_id\t$result_ts $result_time\t$is_hit_target"

    local serv_id=$(upsert_service_id "$service_id")
    if [[ -z "$result_ts" ]]; then
        sqlite3 "$DB_PATH" "INSERT INTO shots (target_id, service_id, timestamp) VALUES ('$target_id', '$serv_id', '$ts $time');"
        ((ammo[$service_id]--))
        echo -e "$ts $time\t$service_id\tВыстрел по ID:$target_id\tБоезапас: ${ammo[$service_id]}" >>"$KP_LOG_PATH"
        # echo -e "$ts $time\t$service_id\tВыстрел по ID:$target_id\tБоезапас: ${ammo[$service_id]}"
    else
        local last_id=$(sqlite3 "$DB_PATH" "SELECT id FROM shots WHERE target_id='$target_id' AND service_id='$serv_id' AND timestamp='$ts $time' ORDER BY id DESC LIMIT 1;")
        sqlite3 "$DB_PATH" "UPDATE shots SET is_hit_target=$is_hit_target, hit_target_ts='$result_ts $result_time' WHERE id=$last_id;"
        echo -e "$ts $time\t$service_id\t$([[ $is_hit_target == 1 ]] && echo 'Попадание' || echo 'Промах') по ID:$target_id при выстреле в $result_ts $result_time" >>"$KP_LOG_PATH"
        # echo -e "$ts $time\t$service_id\t$([[ $is_hit_target == 1 ]] && echo 'Попадание' || echo 'Промах') по ID:$target_id при выстреле в $result_ts $result_time"
    fi

    rm -f "$file"
}

declare -A ammo

# Пополение боекомплекта
handle_ammo() {
    local msg="$1" file="$2"
    read -r ts time service_id count <<<"$msg"
    
	ammo["$service_id"]=$count

	echo -e "$ts $time\t$service_id\tAMMO\t$count"
	echo -e "$ts $time\t$service_id\tБоезапас пополнен на $count снарядов" >>"$KP_LOG_PATH"

	local serv_id=$(upsert_service_id "$service_id")
    sqlite3 "$DB_PATH" "INSERT INTO ammo (service_id, count, timestamp) VALUES ('$serv_id', $count, '$ts $time');"

    rm -f "$file"
}

declare -A services_map=(
	["zrdn1"]="ЗРДН1"
	["zrdn2"]="ЗРДН2"
	["zrdn3"]="ЗРДН3"
	["spro"]="СПРО"
	["rls1"]="РЛС1"
	["rls2"]="РЛС2"
	["rls3"]="РЛС3"
)

declare -A service_status

for key in "${!services_map[@]}"; do
	service_status["$key"]=1 # 1 - работает
done

health_check() {
	while true; do
		for key in "${!services_map[@]}"; do
			if [[ ! -f "$PING_DIR/ping_$key" ]]; then
                # echo "PING $key" # TODO: think about
				touch "$PING_DIR/ping_$key"
			fi
		done

		sleep 30

		for key in "${!services_map[@]}"; do
			if [[ -f "$PING_DIR/ping_$key" ]]; then
				# Если система впервые перестала работать, выводим сообщение
				if [[ ${service_status[$key]} -eq 1 ]]; then
					check_time=$(date '+%d-%m %H:%M:%S.%3N')
					echo "$check_time ${services_map[$key]} is NOT AVAILABLE"
					echo "$check_time ${services_map[$key]} is NOT AVAILABLE" >>"$KP_LOG_PATH"
					service_status["$key"]=0 # Отмечаем как неработающую
				fi
			else
				# Если система была неработающей, но теперь отвечает, выводим сообщение о восстановлении
				if [[ ${service_status[$key]} -eq 0 ]]; then
					check_time=$(date '+%d-%m %H:%M:%S.%3N')
					echo "$check_time ${services_map[$key]} is AVAILABLE"
					echo "$check_time ${services_map[$key]} is AVAILABLE" >>"$KP_LOG_PATH"
					service_status["$key"]=1 # Отмечаем как работающую
				fi
			fi
			rm -f "$PING_DIR/pong_$key"
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
			handle_detect "$decrypted_message" "$file"
		elif [[ "$file" == "$SHOOTING_DIR/"* ]]; then
			handle_shot "$decrypted_message" "$file"
		elif [[ "$file" == "$AMMO_DIR/"* ]]; then
			handle_ammo "$decrypted_message" "$file"
		fi
	done
	sleep 0.01
done