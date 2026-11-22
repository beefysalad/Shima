#!/usr/bin/env bash
# Usage: scripts/verify-alignment.sh [--live | --live-frame-only | --expanded | --menus | --settings [pid]]
cd "$(dirname "$0")/.."
exec swift scripts/shima-windows.swift "$@"
