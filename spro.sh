#!/bin/bash

source internal.sh
source utils/const.sh
source utils/common.sh

# ./spro.sh 3150000 3750000 1200000
# Проверяем, переданы ли параметры
if [[ $# -ne 3 ]]; then
    echo "Использование: $0 <X_координата> <Y_координата> <Радиус действия>"
    exit 1
fi

[[ $EUID -eq 0 ]] && { echo "Запуск от root запрещен"; exit 1; }
[[ "$(uname)" != "Linux" ]] && { echo "Скрипт поддерживается только в Linux"; exit 1; }
[[ -z "$BASH_VERSION" ]] && { echo "Скрипт должен выполняться в Bash"; exit 1; }

SPRO_X=$1
SPRO_Y=$2
SPRO_RADIUS=$3

# Путь к файлу с обработанными целями
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROCESSED_FILES="$SCRIPT_DIR/temp/spro_processed_files.txt"
>"$PROCESSED_FILES" # Очистка файла при запуске

# Определяем папку для сообщений и логов
SPRO_LOG="$SCRIPT_DIR/logs/spro_log.txt"
>"$SPRO_LOG" # Очистка файла при запуске

# Боезапас и время пополнения
MISSILES=10
RELOAD_TIME=20     # Время до пополнения (в секундах)
LAST_RELOAD_TIME=0 # Временная метка последней перезарядки

# Ассоциативные массивы
declare -A TARGET_COORDS
declare -A TARGET_TYPE
declare -A TARGET_SHOT_TIME

echo "СПРО запущена!"

defer() {
    echo -e "\nСПРО остановлена!"
    exit 0
}

trap defer SIGINT SIGTERM

encrypt_and_save_message "$AMMO_DIR/" "$(date '+%d-%m %H:%M:%S.%3N') СПРО $MISSILES" &
while true; do
	current_time=$(date +%s)

	# Проверяем пополнение боезапаса
	if ((MISSILES == 0)) && ((current_time - LAST_RELOAD_TIME >= RELOAD_TIME)); then
		MISSILES=10
		LAST_RELOAD_TIME=$current_time
		ammo_time=$(date '+%d-%m %H:%M:%S.%3N')
		echo "$ammo_time СПРО Боезапас пополнен - $MISSILES снарядов"
		encrypt_and_save_message "$AMMO_DIR/" "$ammo_time СПРО $MISSILES" &
		echo "$ammo_time СПРО Боезапас пополнен - $MISSILES снарядов" >>"$SPRO_LOG"
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

			if [[ "${TARGET_TYPE[$target_id]}" == "ББ БР" && -n "${TARGET_SHOT_TIME[$target_id]}" ]]; then
				miss_time=$(date '+%d-%m %H:%M:%S.%3N')
				echo "$miss_time СПРО Промах по цели ID:$target_id при выстреле в ${TARGET_SHOT_TIME[$target_id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$target_id]} СПРО $target_id $miss_time 0" &
				echo "$miss_time СПРО Промах по цели ID:$target_id при выстреле в ${TARGET_SHOT_TIME[$target_id]}" >>"$SPRO_LOG"
				unset TARGET_SHOT_TIME["$target_id"]
			fi

			x=$(grep -oP 'X:\s*\K\d+' "$target_file")
			y=$(grep -oP 'Y:\s*\K\d+' "$target_file")

			dist_to_target=$(distance "$SPRO_X" "$SPRO_Y" "$x" "$y")
			if (($(echo "$dist_to_target <= $SPRO_RADIUS" | bc -l))); then
				if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then
					if [[ -z "${TARGET_TYPE[$target_id]}" ]]; then
						prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
						prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

						speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
						target_type=$(get_target_type "$speed")
						TARGET_TYPE["$target_id"]="$target_type"

						if [[ "${TARGET_TYPE[$target_id]}" == "ББ БР" ]]; then
							detection_time=$(date '+%d-%m %H:%M:%S.%3N')
							echo "$detection_time СПРО Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
							encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time СПРО $target_id X:$x Y:$y $speed ${TARGET_TYPE[$target_id]}" &
							echo "$detection_time СПРО Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ${TARGET_TYPE[$target_id]}" >>"$SPRO_LOG"
						fi
					fi

					if [[ "${TARGET_TYPE[$target_id]}" == "ББ БР" ]]; then
						if ((MISSILES > 0)); then
							((MISSILES--))
							shot_time=$(date '+%d-%m %H:%M:%S.%3N')
							echo "$shot_time СПРО Выстрел по цели ID:$target_id. Осталось снарядов: $MISSILES"
							encrypt_and_save_message "$SHOOTING_DIR/" "$shot_time СПРО $target_id" &
							echo "$shot_time СПРО Выстрел по цели ID:$target_id. Осталось снарядов: $MISSILES" >>"$SPRO_LOG"
							echo "СПРО" >"$DESTROY_DIR/$target_id"
							TARGET_SHOT_TIME["$target_id"]="$shot_time"

							if ((MISSILES == 0)); then
								LAST_RELOAD_TIME=$(date +%s)
								echo "$(date '+%d-%m %H:%M:%S.%3N') СПРО Боезапас исчерпан! Начинается перезарядка"
							fi
						else
							echo "$(date '+%d-%m %H:%M:%S.%3N') СПРО Невозможно атаковать цель ID:$target_id - Боезапас исчерпан"
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
			if [[ "${TARGET_TYPE[$id]}" == "ББ БР" && -n "${TARGET_SHOT_TIME[$id]}" ]]; then
				destruction_time=$(date '+%d-%m %H:%M:%S.%3N')
				echo "$destruction_time СПРО Уничтожена цель ID:$id при выстреле в ${TARGET_SHOT_TIME[$id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$id]} СПРО $id $destruction_time 1" &
				echo "$destruction_time СПРО Уничтожена цель ID:$id при выстреле в ${TARGET_SHOT_TIME[$id]}" >>"$SPRO_LOG"
				unset TARGET_SHOT_TIME["$id"]
			fi
		fi
	done

	process_ping "spro" &

	trim_log_file "$SPRO_LOG"
done