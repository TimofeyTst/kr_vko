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

SERVICE_ID="СПРО"

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

echo "$SERVICE_ID запущена"

defer() {
    echo -e "\n$SERVICE_ID остановлена"
    exit 0
}

trap defer SIGINT SIGTERM

encrypt_and_save_message "$AMMO_DIR/" "$(date '+%d-%m %H:%M:%S.%3N') $SERVICE_ID $MISSILES" &
while true; do
	current_time=$(date +%s)

	# Проверяем пополнение боезапаса
	if ((MISSILES == 0)) && ((current_time - LAST_RELOAD_TIME >= RELOAD_TIME)); then
		MISSILES=10
		LAST_RELOAD_TIME=$current_time
		ammo_time=$(date '+%d-%m %H:%M:%S.%3N')
		echo "$ammo_time $SERVICE_ID Боезапас пополнен - $MISSILES снарядов"
		encrypt_and_save_message "$AMMO_DIR/" "$ammo_time $SERVICE_ID $MISSILES" &
		echo "$ammo_time $SERVICE_ID Боезапас пополнен - $MISSILES снарядов" >>"$SPRO_LOG"
	fi

	unset CURRENT_TARGETS_PACKAGE
	declare -A CURRENT_TARGETS_PACKAGE
	found_repeated_target=false

	while ! $found_repeated_target; do
		# Получаем последние MAX_FILES файлов, отсортированные по времени
		mapfile -t latest_files < <(ls -lt "$TARGETS_DIR" 2>/dev/null | head -n "$MAX_FILES" | awk '{print $9}')

		for target_file in "${latest_files[@]}"; do
			if grep -qFx "$target_file" "$PROCESSED_FILES"; then
				continue
			fi

			if [[ ${#target_file} -le 2 ]]; then
				echo "$target_file" >>"$PROCESSED_FILES"
				continue
			fi

			target_id=$(decode_target_id "$target_file")

			# Если началась новая пачка (найден повторный таргет), то завершаем проверку целей
			if [[ -n "${CURRENT_TARGETS_PACKAGE[$target_id]}" ]]; then
				found_repeated_target=true
				break
			fi

			CURRENT_TARGETS_PACKAGE["$target_id"]="$target_file"
			echo "$target_file" >>"$PROCESSED_FILES"

			if [[ -n "${TARGET_SHOT_TIME[$target_id]}" ]]; then
				miss_time=$(date '+%d-%m %H:%M:%S.%3N')
				echo "$miss_time $SERVICE_ID Промах по цели ID:$target_id при выстреле в ${TARGET_SHOT_TIME[$target_id]}"
				encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$target_id]} $SERVICE_ID $target_id $miss_time 0" &
				echo "$miss_time $SERVICE_ID Промах по цели ID:$target_id при выстреле в ${TARGET_SHOT_TIME[$target_id]}" >>"$SPRO_LOG"
				unset TARGET_SHOT_TIME["$target_id"]
			fi

			x=$(grep -oP 'X:\s*\K\d+' "$TARGETS_DIR/$target_file")
			y=$(grep -oP 'Y:\s*\K\d+' "$TARGETS_DIR/$target_file")

			dist_to_target=$(distance "$SPRO_X" "$SPRO_Y" "$x" "$y")
			if (($(echo "$dist_to_target > $SPRO_RADIUS" | bc -l))); then
				continue
			fi

			if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then
				if [[ -z "${TARGET_TYPE[$target_id]}" ]]; then
					prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
					prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

					speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
					target_type=$(get_target_type "$speed")
					TARGET_TYPE["$target_id"]="$target_type"

					if [[ "${TARGET_TYPE[$target_id]}" == "ББ БР" ]]; then
						detection_time=$(date '+%d-%m %H:%M:%S.%3N')
						echo "$detection_time $SERVICE_ID Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
						encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time $SERVICE_ID $target_id X:$x Y:$y $speed ${TARGET_TYPE[$target_id]}" &
						echo "$detection_time $SERVICE_ID Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ${TARGET_TYPE[$target_id]}" >>"$SPRO_LOG"
					fi
				fi

				if [[ "${TARGET_TYPE[$target_id]}" == "ББ БР" ]]; then
					if ((MISSILES > 0)); then
						((MISSILES--))
						shot_time=$(date '+%d-%m %H:%M:%S.%3N')
						echo "$shot_time $SERVICE_ID Выстрел по цели ID:$target_id. Осталось снарядов: $MISSILES"
						encrypt_and_save_message "$SHOOTING_DIR/" "$shot_time $SERVICE_ID $target_id" &
						echo "$shot_time $SERVICE_ID Выстрел по цели ID:$target_id. Осталось снарядов: $MISSILES" >>"$SPRO_LOG"
						echo "$SERVICE_ID" >"$DESTROY_DIR/$target_id"
						TARGET_SHOT_TIME["$target_id"]="$shot_time"

						if ((MISSILES == 0)); then
							LAST_RELOAD_TIME=$(date +%s)
							echo "$(date '+%d-%m %H:%M:%S.%3N') $SERVICE_ID Боезапас исчерпан! Начинается перезарядка"
						fi
					else
						echo "$(date '+%d-%m %H:%M:%S.%3N') $SERVICE_ID Невозможно атаковать цель ID:$target_id - Боезапас исчерпан"
					fi
				fi
			fi
			TARGET_COORDS["$target_id"]="$x,$y"
		done

		if ! $found_repeated_target; then
			sleep 0.01 # если не было второй пачки то ждем ее генерации, иначе сразу процессим 
		fi
	done

	# Для каждой цели в которую стреляли если не нашли в текущей пачке, то мы ее уничтожили
	for id in "${!TARGET_SHOT_TIME[@]}"; do
		# Проверяем, не существует ли цель в текущей пачке
		if [[ -z "${CURRENT_TARGETS_PACKAGE[$id]}" ]]; then
			destruction_time=$(date '+%d-%m %H:%M:%S.%3N')
			echo "$destruction_time $SERVICE_ID Уничтожена цель ID:$id при выстреле в ${TARGET_SHOT_TIME[$id]}"
			encrypt_and_save_message "$SHOOTING_DIR/" "${TARGET_SHOT_TIME[$id]} $SERVICE_ID $id $destruction_time 1" &
			echo "$destruction_time $SERVICE_ID Уничтожена цель ID:$id при выстреле в ${TARGET_SHOT_TIME[$id]}" >>"$SPRO_LOG"
			# очищаем память
			unset TARGET_SHOT_TIME["$id"]
			unset TARGET_COORDS["$id"]
			unset TARGET_TYPE["$id"]
		fi
	done

	process_ping "spro" &

	trim_log_file "$SPRO_LOG"
done