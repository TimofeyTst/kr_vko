#!/bin/bash

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

