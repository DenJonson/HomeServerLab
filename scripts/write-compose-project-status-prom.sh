#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${HOMELAB_TEXTFILE_DIR:-/opt/homelab/node-exporter/textfile}"
OUT_FILE="${OUT_DIR}/compose_projects.prom"
TMP_FILE="${OUT_FILE}.$$"
DOCKER_BIN="${DOCKER_BIN:-docker}"

mkdir -p "${OUT_DIR}"

declare -A project_total=()
declare -A project_running=()
declare -A project_healthy=()
declare -A project_unhealthy=()
declare -A service_total=()
declare -A service_healthy=()
declare -A projects=()
declare -A services=()

escape_label() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  printf '%s' "${value}"
}

inc() {
  local name="$1"
  local current="${!name:-0}"
  printf -v "${name}" '%s' "$((current + 1))"
}

containers="$("${DOCKER_BIN}" ps -aq --filter label=com.docker.compose.project || true)"

if [[ -n "${containers}" ]]; then
  while IFS='|' read -r project service _name status health; do
    [[ -z "${project}" ]] && continue
    [[ -z "${service}" ]] && service="unknown"

    projects["${project}"]=1
    services["${project}|${service}"]=1

    inc "project_total[${project}]"
    inc "service_total[${project}|${service}]"

    if [[ "${status}" == "running" ]]; then
      inc "project_running[${project}]"
    fi

    if [[ "${status}" == "running" && ( "${health}" == "healthy" || "${health}" == "none" ) ]]; then
      inc "project_healthy[${project}]"
      inc "service_healthy[${project}|${service}]"
    fi

    if [[ "${health}" == "unhealthy" || "${health}" == "starting" || "${status}" != "running" ]]; then
      inc "project_unhealthy[${project}]"
    fi
  done < <("${DOCKER_BIN}" inspect \
    --format '{{ index .Config.Labels "com.docker.compose.project" }}|{{ index .Config.Labels "com.docker.compose.service" }}|{{ .Name }}|{{ .State.Status }}|{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}none{{ end }}' \
    ${containers})
fi

if [[ -n "${HOMELAB_EXPECTED_COMPOSE_PROJECTS:-}" ]]; then
  IFS=',' read -ra expected_projects <<< "${HOMELAB_EXPECTED_COMPOSE_PROJECTS}"
  for raw_project in "${expected_projects[@]}"; do
    project="$(printf '%s' "${raw_project}" | xargs)"
    [[ -n "${project}" ]] && projects["${project}"]=1
  done
fi

{
  cat <<'EOF'
# HELP homelab_compose_project_up 1 when all known containers in a compose project are running and healthy, otherwise 0.
# TYPE homelab_compose_project_up gauge
# HELP homelab_compose_project_degraded 1 when at least one known container in a compose project is stopped, starting, unhealthy, or missing.
# TYPE homelab_compose_project_degraded gauge
# HELP homelab_compose_project_containers Number of known containers in a compose project.
# TYPE homelab_compose_project_containers gauge
# HELP homelab_compose_project_running_containers Number of running containers in a compose project.
# TYPE homelab_compose_project_running_containers gauge
# HELP homelab_compose_project_healthy_containers Number of running and healthy containers in a compose project.
# TYPE homelab_compose_project_healthy_containers gauge
# HELP homelab_compose_service_up 1 when all known containers for a compose service are running and healthy, otherwise 0.
# TYPE homelab_compose_service_up gauge
# HELP homelab_compose_exporter_last_success_unixtime Unix timestamp of the last successful compose status export.
# TYPE homelab_compose_exporter_last_success_unixtime gauge
EOF

  printf 'homelab_compose_exporter_last_success_unixtime %s\n' "$(date +%s)"

  for project in "${!projects[@]}"; do
    total="${project_total[${project}]:-0}"
    running="${project_running[${project}]:-0}"
    healthy="${project_healthy[${project}]:-0}"
    unhealthy="${project_unhealthy[${project}]:-0}"
    up=0
    degraded=1

    if [[ "${total}" -gt 0 && "${total}" -eq "${running}" && "${total}" -eq "${healthy}" && "${unhealthy}" -eq 0 ]]; then
      up=1
      degraded=0
    fi

    safe_project="$(escape_label "${project}")"
    printf 'homelab_compose_project_up{project="%s"} %s\n' "${safe_project}" "${up}"
    printf 'homelab_compose_project_degraded{project="%s"} %s\n' "${safe_project}" "${degraded}"
    printf 'homelab_compose_project_containers{project="%s"} %s\n' "${safe_project}" "${total}"
    printf 'homelab_compose_project_running_containers{project="%s"} %s\n' "${safe_project}" "${running}"
    printf 'homelab_compose_project_healthy_containers{project="%s"} %s\n' "${safe_project}" "${healthy}"
  done

  for key in "${!services[@]}"; do
    project="${key%%|*}"
    service="${key#*|}"
    total="${service_total[${key}]:-0}"
    healthy="${service_healthy[${key}]:-0}"
    up=0

    if [[ "${total}" -gt 0 && "${total}" -eq "${healthy}" ]]; then
      up=1
    fi

    printf 'homelab_compose_service_up{project="%s",service="%s"} %s\n' \
      "$(escape_label "${project}")" \
      "$(escape_label "${service}")" \
      "${up}"
  done
} > "${TMP_FILE}"

mv "${TMP_FILE}" "${OUT_FILE}"
