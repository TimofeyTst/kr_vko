#!/bin/bash

source utils/const.sh

defer() {
    echo "Остановка всех скриптов..."
    # Завершаем все дочерние процессы текущего скрипта
    pkill -P $$  # Убивает все процессы, запущенные этим скриптом
    exit 0
}

trap defer SIGINT SIGTERM

# Компиляция C файлов
INTERNAL_DIR="./internal"
echo "Компиляция C-файлов..."

gcc -o "$BIN_DIR/distance" "$INTERNAL_DIR/distance.c" -lm
gcc -o "$BIN_DIR/is_in_sector" "$INTERNAL_DIR/is_in_sector.c" -lm
gcc -o "$BIN_DIR/is_trajectory_crossing_circle" "$INTERNAL_DIR/is_trajectory_crossing_circle.c" -lm
echo "Компиляция C-файлов завершена"

echo "Запуск всех скриптов..."
find "$MESSAGES_DIR" -type f -name "*" -exec rm -f {} \;

./rls.sh 1 2500000 3600000 6000000 90 90 3250000 5250000 1400000 &
./rls.sh 2 12000000 5000000 3500000 90 120 3250000 5250000 1400000 &
./rls.sh 3 4000000 3800000 4000000 270 200 3250000 5250000 1400000 &
./spro.sh 3250000 3750000 1400000 &
./zrdn.sh 1 5050000 5300000 600000 &
./zrdn.sh 2 2900000 5750000 400000 &
./zrdn.sh 3 2600000 2750000 550000 &

wait # Ожидание завершения всех процессов

echo -e "\nВсе скрипты завершены"
