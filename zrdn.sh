#!/bin/bash

source internal.sh
source utils/const.sh
source utils/common.sh

# ./zrdn.sh 1 9200000 4500000 2000000
# Проверяем, переданы ли параметры
if [[ $# -ne 4 ]]; then
	echo "Использование: $0 <Номер_ЗРДН> <X_координата> <Y_координата> <Радиус действия>"
	exit 1
fi

[[ $EUID -eq 0 ]] && { echo "Запуск от root запрещен"; exit 1; }
[[ "$(uname)" != "Linux" ]] && { echo "Скрипт поддерживается только в Linux"; exit 1; }
[[ -z "$BASH_VERSION" ]] && { echo "Скрипт должен выполняться в Bash"; exit 1; }

ZRDN_ID=$1
ZRDN_X=$2
ZRDN_Y=$3
ZRDN_RADIUS=$4

# Путь к файлу с обработанными целями
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROCESSED_FILES="$SCRIPT_DIR/temp/zrdn${ZRDN_ID}_processed_files.txt"
>"$PROCESSED_FILES" # Очистка файла при запуске

# Определяем папку для сообщений и логов
ZRDN_LOG="$SCRIPT_DIR/logs/zrdn${ZRDN_ID}_log.txt"
>"$ZRDN_LOG" # Очистка файла при запуске

# Боезапас и время пополнения
MISSILES=20
RELOAD_TIME=10     # Время до пополнения (в секундах)
LAST_RELOAD_TIME=0 # Временная метка последней перезарядки

# Ассоциативные массивы
declare -A TARGET_COORDS
declare -A TARGET_TYPE
declare -A TARGET_SHOT_TIME

echo "ЗРДН${ZRDN_ID} запущена!"

defer() {
	echo -e "\nЗРДН$ZRDN_ID остановлена!"
	exit 0
}

trap defer SIGINT SIGTERM

encrypt_and_save_message "$AMMO_DIR/" "$(date '+%d-%m %H:%M:%S.%3N') ЗРДН$ZRDN_ID $MISSILES" &
while true; do
	current_time=$(date +%s)

	# Проверяем пополнение боезапаса
	if ((MISSILES == 0)) && ((current_time - LAST_RELOAD_TIME >= RELOAD_TIME)); then
		MISSILES=20
		LAST_RELOAD_TIME=$current_time
		ammo_time=$(date '+%d-%m %H:%M:%S.%3N')
		echo "$ammo_time ЗРДН$ZRDN_ID Боезапас пополнен - $MISSILES снарядов"
		encrypt_and_save_message "$AMMO_DIR/" "$ammo_time ЗРДН$ZRDN_ID $MISSILES" &
		echo "$ammo_time ЗРДН$ZRDN_ID Боезапас пополнен - $MISSILES снарядов" >>"$ZRDN_LOG"
	fi

	unset FIRST_TARGET_FILE
	declare -A FIRST_TARGET_FILE
	found_second_file=false

	while ! $found_second_file; do
		# Получаем последние MAX_FILES файлов, отсортированные по времени
		mapfile -t latest_files < <(find "$TARGETS_DIR" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n "$MAX_FILES" | cut -d' ' -f2-)

		for target_file in "${latest_files[@]}"; do
			filename=$(basename "$target_file")

			if grep -qFx "$filename" "$PROCESSED_FILES"; then
				continue
			fi

			if [[ ${#filename} -le 2 ]]; then
				echo "$filename" >>"$PROCESSED_FILES"
				continue
			fi

			target_id=$(decode_target_id "$filename")

			# Если для этой цели уже был найден файл — завершаем поиск
			if [[ -n "${FIRST_TARGET_FILE[$target_id]}" ]]; then
				found_second_file=true
				break
			fi

			FIRST_TARGET_FILE["$target_id"]="$target_file"
			echo "$filename" >>"$PROCESSED_FILES"

			if [[ ("${TARGET_TYPE[$target_id]}" == "Крылатая ракета" || "${TARGET_TYPE[$target_id]}" == "Самолет") && -n "${TARGET_SHOT_TIME[$target_id]}" ]]; then
				miss_time=$(date '+%d-%m %H:%M:%S.%3N')
				echo "$miss_time ЗРДН$ZRDN_ID Промах по цели ID:$target_id при выстреле в ${TARGET_SHOT_TIME[$target_id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$target_id]} ЗРДН$ZRDN_ID $target_id $miss_time 0" &
				echo "$miss_time ЗРДН$ZRDN_ID Промах по цели ID:$target_id при выстреле в ${TARGET_SHOT_TIME[$target_id]}" >>"$ZRDN_LOG"
				unset TARGET_SHOT_TIME["$target_id"]
			fi

			x=$(grep -oP 'X:\s*\K\d+' "$target_file")
			y=$(grep -oP 'Y:\s*\K\d+' "$target_file")

			dist_to_target=$(distance "$ZRDN_X" "$ZRDN_Y" "$x" "$y")
			if (($(echo "$dist_to_target <= $ZRDN_RADIUS" | bc -l))); then
				if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then
					if [[ -z "${TARGET_TYPE[$target_id]}" ]]; then
						prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
						prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

						speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
						target_type=$(get_target_type "$speed")
						TARGET_TYPE["$target_id"]="$target_type"

						if [[ "${TARGET_TYPE[$target_id]}" == "Крылатая ракета" || "${TARGET_TYPE[$target_id]}" == "Самолет" ]]; then
							detection_time=$(date '+%d-%m %H:%M:%S.%3N')
							echo "$detection_time ЗРДН$ZRDN_ID Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
							encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time ЗРДН$ZRDN_ID $target_id X:$x Y:$y $speed ${TARGET_TYPE[$target_id]}" &
							echo "$detection_time ЗРДН$ZRDN_ID Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ${TARGET_TYPE[$target_id]}" >>"$ZRDN_LOG"
						fi
					fi

					if [[ "${TARGET_TYPE[$target_id]}" == "Крылатая ракета" || "${TARGET_TYPE[$target_id]}" == "Самолет" ]]; then
						if ((MISSILES > 0)); then
							((MISSILES--))
							shot_time=$(date '+%d-%m %H:%M:%S.%3N')
							echo "$shot_time ЗРДН$ZRDN_ID Выстрел по цели ID:$target_id. Осталось снарядов: $MISSILES"
							encrypt_and_save_message "$SHOOTING_DIR/" "$shot_time ЗРДН$ZRDN_ID $target_id" &
							echo "$shot_time ЗРДН$ZRDN_ID Выстрел по цели ID:$target_id. Осталось снарядов: $MISSILES" >>"$ZRDN_LOG"
							echo "ЗРДН$ZRDN_ID" >"$DESTROY_DIR/$target_id"
							TARGET_SHOT_TIME["$target_id"]="$shot_time"

							if ((MISSILES == 0)); then
								LAST_RELOAD_TIME=$(date +%s)
								echo "$(date '+%d-%m %H:%M:%S.%3N') ЗРДН$ZRDN_ID Боезапас исчерпан! Начинается перезарядка"
							fi
						else
							echo "$(date '+%d-%m %H:%M:%S.%3N') ЗРДН$ZRDN_ID Невозможно атаковать цель ID:$target_id - Боезапас исчерпан"
						fi
					fi
				fi
				TARGET_COORDS["$target_id"]="$x,$y"
			fi
		done

		if ! $found_second_file; then
			sleep 0.01
		fi
	done

	for id in "${!TARGET_COORDS[@]}"; do
		if [[ -z "${FIRST_TARGET_FILE[$id]}" ]]; then
			if [[ ("${TARGET_TYPE[$id]}" == "Крылатая ракета" || "${TARGET_TYPE[$id]}" == "Самолет") && -n "${TARGET_SHOT_TIME[$id]}" ]]; then
				destruction_time=$(date '+%d-%m %H:%M:%S.%3N')
				echo "$destruction_time ЗРДН$ZRDN_ID Уничтожена цель ID:$id при выстреле в ${TARGET_SHOT_TIME[$id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$id]} ЗРДН$ZRDN_ID $id $destruction_time 1" &
				echo "$destruction_time ЗРДН$ZRDN_ID Уничтожена цель ID:$id при выстреле в ${TARGET_SHOT_TIME[$id]}" >>"$ZRDN_LOG"
				unset TARGET_SHOT_TIME["$id"]
			fi
		fi
	done

	process_ping "zrdn$ZRDN_ID" &
	total_lines=$(wc -l <"$ZRDN_LOG")
	if ((total_lines > 100)); then
		temp_file=$(mktemp) # Временный файл
		tail -n 100 "$ZRDN_LOG" >"$temp_file"
		mv "$temp_file" "$ZRDN_LOG"
	fi
done
