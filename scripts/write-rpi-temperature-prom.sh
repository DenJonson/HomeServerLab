#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="/opt/homelab/node-exporter/textfile"
OUT_FILE="${OUT_DIR}/raspberrypi_temperature.prom"
TMP_FILE="${OUT_FILE}.$$"

RAW_TEMP_FILE="/sys/class/thermal/thermal_zone0/temp"

mkdir -p "${OUT_DIR}"

if [[ ! -r "${RAW_TEMP_FILE}" ]]; then
  echo "ERROR: cannot read ${RAW_TEMP_FILE}" >&2
  exit 1
fi

raw_temp="$(cat "${RAW_TEMP_FILE}")"

if ! [[ "${raw_temp}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: invalid temperature value: ${raw_temp}" >&2
  exit 1
fi

temp_c="$(awk "BEGIN { printf \"%.3f\", ${raw_temp} / 1000 }")"

cat > "${TMP_FILE}" <<EOF
# HELP raspberrypi_cpu_temperature_celsius Raspberry Pi CPU temperature in Celsius.
# TYPE raspberrypi_cpu_temperature_celsius gauge
raspberrypi_cpu_temperature_celsius ${temp_c}
EOF

mv "${TMP_FILE}" "${OUT_FILE}"