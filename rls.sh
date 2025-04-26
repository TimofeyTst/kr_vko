#!/bin/bash

source internal.sh
source utils/const.sh
source utils/common.sh

# Проверяем, переданы ли параметры
if [[ $# -ne 9 ]]; then
	echo "Использование: $0 <Номер_РЛС> <X_координата> <Y_координата> <Радиус действия> <Азимут> <Угол обзора> <СПРО_X_координата> <СПРО_Y_координата> <СПРО Радиус действия>"
	exit 1
fi

[[ $EUID -eq 0 ]] && { echo "Запуск от root запрещен"; exit 1; }
[[ "$(uname)" != "Linux" ]] && { echo "Скрипт поддерживается только в Linux"; exit 1; }
[[ -z "$BASH_VERSION" ]] && { echo "Скрипт должен выполняться в Bash"; exit 1; }

RLS_ID=$1
RLS_X=$2
RLS_Y=$3
RLS_RADIUS=$4
RLS_ALPHA=$5
RLS_ANGLE=$6

SPRO_X=$7
SPRO_Y=$8
SPRO_RADIUS=$9

# Путь к файлу с обработанными целями
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROCESSED_FILES="$SCRIPT_DIR/temp/rls${RLS_ID}_processed_files.txt"
>"$PROCESSED_FILES" # Очистка файла при запуске

# Определяем папку для сообщений и логов
MESSAGES_DIR="$SCRIPT_DIR/messages"
RLS_LOG="$SCRIPT_DIR/logs/rls${RLS_ID}_log.log"
>"$RLS_LOG" # Очистка файла при запуске

# Ассоциативные массивы
declare -A TARGET_COORDS
declare -A TARGET_TYPE

echo "РЛС${RLS_ID} запущена"

defer() {
	echo -e "\РЛС$RLS_ID остановлена"
	exit 0
}

trap defer SIGINT SIGTERM

while true; do
	# Получаем последние MAX_FILES файлов, отсортированные по времени
	mapfile -t latest_files < <(find "$TARGETS_DIR" -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n "$MAX_FILES" | cut -d' ' -f2-)

	for target_file in "${latest_files[@]}"; do
		filename=$(basename "$target_file")

		if grep -qFx "$filename" "$PROCESSED_FILES"; then
			continue
		fi

		if [[ ${#filename} -le 2 ]]; then # Если файл битый (после уничтожения)
			echo "$filename" >>"$PROCESSED_FILES"
			continue
		fi

		target_id=$(decode_target_id "$filename")
		echo "$filename" >>"$PROCESSED_FILES"

		# Если цель уже известного типа, пропустить
		if [[ -n "${TARGET_TYPE[$target_id]}" ]]; then
			continue
		fi


		x=$(grep -oP 'X:\s*\K\d+' "$target_file")
		y=$(grep -oP 'Y:\s*\K\d+' "$target_file")

		# Пропустить цель, если она находится вне радиуса РЛС
		dist_to_target=$(distance "$RLS_X" "$RLS_Y" "$x" "$y")
		if (($(echo "$dist_to_target > $RLS_RADIUS" | bc -l))); then
			continue
		fi

		# Проверка, находится ли цель в секторе
		target_in_sector=$(is_in_sector "$x" "$y" "$RLS_ALPHA" "$RLS_ANGLE")
		if [[ "$target_in_sector" -ne 1 ]]; then
			continue
		fi

		if [[ -n "${TARGET_COORDS[$target_id]}" ]]; then
			prev_x=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f1)
			prev_y=$(echo "${TARGET_COORDS[$target_id]}" | cut -d',' -f2)

			speed=$(distance "$prev_x" "$prev_y" "$x" "$y")
			target_type=$(get_target_type "$speed")
			TARGET_TYPE["$target_id"]="$target_type"

			if [[ $target_type == "ББ БР" ]]; then
				detection_time=$(date '+%d-%m %H:%M:%S.%3N')
				echo "$detection_time РЛС$RLS_ID Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ($target_type)"
				echo "$detection_time РЛС$RLS_ID Обнаружена цель ID:$target_id с координатами X:$x Y:$y, скорость: $speed м/с ${TARGET_TYPE[$target_id]}" >>"$RLS_LOG"
				if [[ $(is_trajectory_crossing_circle "$prev_x" "$prev_y" "$x" "$y") -eq 1 ]]; then
					echo "$detection_time РЛС$RLS_ID Цель ID:$target_id движется в сторону СПРО"
					encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time РЛС$RLS_ID $target_id X:$x Y:$y $speed ББ БР-СПРО" &
					echo "$detection_time РЛС$RLS_ID Цель ID:$target_id движется в сторону СПРО" >>"$RLS_LOG"
				else
					encrypt_and_save_message "$DETECTIONS_DIR/" "$detection_time РЛС$RLS_ID $target_id X:$x Y:$y $speed ББ БР" &
				fi
			fi
		fi
		TARGET_COORDS["$target_id"]="$x,$y"
	done

	process_ping "rls$RLS_ID" &

	trim_log_file "$RLS_LOG"

	sleep 0.01
done
