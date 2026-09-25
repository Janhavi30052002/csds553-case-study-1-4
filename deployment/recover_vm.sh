#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy_vm.sh"

LOG_FILE="${HOME}/cs553-recovery.log"
LOCK_FILE="/tmp/cs553-recovery.lock"

VM_HOST="paffenroth-23.dyn.wpi.edu"
VM_PORT="22005"
VM_USER="student-admin"

SSH_KEY="${HOME}/.ssh/ds553_group5_recovery"
AUTHORIZED_KEYS_FILE="${HOME}/group5_authorized_keys"

REPO_URL="https://github.com/kkcham45/csds553-case-study-1-4.git"
REPO_BRANCH="main"
DEPLOY_DIR="/home/student-admin/csds553-case-study-1-4"

SSH_OPTS=(
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=accept-new
    -i "$SSH_KEY"
    -p "$VM_PORT"
)

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

# Check whether the VM is reachable.
if ! ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    "true" >/dev/null 2>&1; then

    log "VM unreachable; starting automated deployment."

    VM_HOST="$VM_HOST" \
    VM_PORT="$VM_PORT" \
    VM_USER="$VM_USER" \
    SSH_KEY="$SSH_KEY" \
    AUTHORIZED_KEYS_FILE="$AUTHORIZED_KEYS_FILE" \
    REPO_URL="$REPO_URL" \
    REPO_BRANCH="$REPO_BRANCH" \
    DEPLOY_DIR="$DEPLOY_DIR" \
    "$DEPLOY_SCRIPT" >> "$LOG_FILE" 2>&1

    exit $?
fi

# VM is reachable; check whether the application service is healthy.
SERVICE_STATE="$(
    ssh "${SSH_OPTS[@]}" \
        "${VM_USER}@${VM_HOST}" \
        "systemctl is-active studymate.service 2>/dev/null || true"
)"

if [[ "$SERVICE_STATE" == "active" ]]; then
    exit 0
fi

log "StudyMate service state is '$SERVICE_STATE'; attempting restart."

if ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    "sudo -n systemctl restart studymate.service" >/dev/null 2>&1; then

    sleep 3

    SERVICE_STATE="$(
        ssh "${SSH_OPTS[@]}" \
            "${VM_USER}@${VM_HOST}" \
            "systemctl is-active studymate.service 2>/dev/null || true"
    )"

    if [[ "$SERVICE_STATE" == "active" ]]; then
        log "StudyMate service recovered successfully."
        exit 0
    fi
fi

log "Service restart failed; starting automated deployment."

VM_HOST="$VM_HOST" \
VM_PORT="$VM_PORT" \
VM_USER="$VM_USER" \
SSH_KEY="$SSH_KEY" \
AUTHORIZED_KEYS_FILE="$AUTHORIZED_KEYS_FILE" \
REPO_URL="$REPO_URL" \
REPO_BRANCH="$REPO_BRANCH" \
DEPLOY_DIR="$DEPLOY_DIR" \
"$DEPLOY_SCRIPT" >> "$LOG_FILE" 2>&1
