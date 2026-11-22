#!/usr/bin/env bash
# Usage: scripts/verify-alignment.sh [--live | --live-frame-only | --expanded | --settings] [pid]
# Use --menus to list menu windows for all apps.
cd "$(dirname "$0")/.."
exec swift scripts/shima-windows.swift "$@"
