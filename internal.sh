#!/bin/bash

source utils/const.sh

distance() {
	./"$BIN_DIR"/distance "$1" "$2" "$3" "$4"
}

# Вычисление попадания между лучами (используем bc)
is_in_sector() {
	./"$BIN_DIR"/is_in_sector "$1" "$2" "$RLS_X" "$RLS_Y" "$RLS_ALPHA" "$RLS_ANGLE"
}

is_trajectory_crossing_circle() {
	./"$BIN_DIR"/is_trajectory_crossing_circle "$1" "$2" "$3" "$4" "$SPRO_X" "$SPRO_Y" "$SPRO_RADIUS"
}