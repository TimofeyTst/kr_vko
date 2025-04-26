#!/bin/bash

BIN_DIR="./bin"
mkdir -p "$BIN_DIR" &>/dev/null

# GenTargets
TARGETS_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"

# Messages
ROOT_DIR=$(dirname "$(realpath "$0")")
MESSAGES_DIR="$ROOT_DIR/messages"
mkdir -p "$MESSAGES_DIR" &>/dev/null

DETECTIONS_DIR="$MESSAGES_DIR/detections"
SHOOTING_DIR="$MESSAGES_DIR/shooting"
PING_DIR="$MESSAGES_DIR/check"
AMMO_DIR="$MESSAGES_DIR/ammo"
mkdir -p "$DETECTIONS_DIR" "$SHOOTING_DIR" "$PING_DIR" "$AMMO_DIR" &>/dev/null
