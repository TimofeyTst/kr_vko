#!/bin/bash

# Ping
process_ping() {
    local service_id="$1"

    ping_file=$(find "$PING_DIR" -type f -name "ping_${service_id}")

    if [[ -n "$ping_file" ]]; then
        rm -f "$ping_file"
        pong_file="$PING_DIR/pong_${service_id}"
        touch "$pong_file"
    fi
}

# Декодирование ID цели из имени файла
decode_target_id() {
	local filename=$1
	local decoded_hex=""
	for ((i = 2; i <= ${#filename}; i += 4)); do
		decoded_hex+="${filename:$i:2}"
	done
	echo -n "$decoded_hex" | xxd -r -p
}

# Генерация случайного имени файла (20 символов) - для сообщений
_generate_random_filename() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1
}

encrypt_and_save_message() {
    local dir_path="$1"
    local content="$2"

    local filename="$(_generate_random_filename)"
    local file_path="${dir_path}${filename}"

    # Создаём контрольную сумму SHA-256
    local checksum=$(echo -n "$content" | sha256sum | cut -d' ' -f1)
    # Шифрование base64
    local encrypted_content=$(echo -n "$content" | base64)

    echo "$checksum $encrypted_content" >"$file_path"
}

# Target type
get_target_type() {
    local speed=$1
    if (( $(echo "$speed >= 8000 && $speed <= 10000" | bc -l) )); then
		echo "ББ БР"
    elif (( $(echo "$speed >= 250 && $speed < 8000" | bc -l) )); then
        if (( $(echo "$speed <= 1000" | bc -l) )); then
            echo "Крылатая ракета"
        else
            echo "Неизвестный тип"
        fi
    elif (( $(echo "$speed >= 50 && $speed < 250" | bc -l) )); then
        echo "Самолет"
    else
        echo "Неизвестный тип"
    fi
}

# old_get_target_type() {
# 	local speed=$1
# 	if (($(echo "$speed >= 8000" | bc -l))); then
# 		echo "ББ БР"
# 	elif (($(echo "$speed >= 250" | bc -l))); then
# 		echo "Крылатая ракета"
# 	else
# 		echo "Самолет"
# 	fi
# }

# Logs
trim_log_file() {
    local log_file="$1"
    local max_lines=100

    total_lines=$(wc -l < "$log_file")
    if (( total_lines > max_lines )); then
        local temp_file=$(mktemp) # Временный файл
        tail -n "$max_lines" "$log_file" > "$temp_file"
        mv "$temp_file" "$log_file"
    fi
}
