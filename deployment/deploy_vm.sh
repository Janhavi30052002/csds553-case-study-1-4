#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# DS/CS 553 Case Study 2
# Automated VM Deployment Script
#
# This script is intended to be run from a trusted Linux host
# (for example, linux.wpi.edu) and deploy the project to the
# WPI VM over SSH.
#
# Required environment variables:
#   VM_HOST
#   VM_PORT
#   VM_USER
#   SSH_KEY
#   AUTHORIZED_KEYS_FILE
#
# Optional:
#   REPO_URL
#   REPO_BRANCH
#   DEPLOY_DIR
#   HF_TOKEN
# ============================================================

: "${VM_HOST:?Set VM_HOST}"
: "${VM_PORT:?Set VM_PORT}"
: "${VM_USER:?Set VM_USER}"
: "${SSH_KEY:?Set SSH_KEY}"
: "${AUTHORIZED_KEYS_FILE:?Set AUTHORIZED_KEYS_FILE}"

REPO_URL="${REPO_URL:-https://github.com/kkcham45/csds553-case-study-1-4.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
DEPLOY_DIR="${DEPLOY_DIR:-/home/${VM_USER}/csds553-case-study-1-4}"

SSH_OPTS=(
    -i "$SSH_KEY"
    -p "$VM_PORT"
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
)

echo "[1/7] Checking local files..."

test -f "$SSH_KEY" || {
    echo "ERROR: SSH private key not found: $SSH_KEY"
    exit 1
}

test -f "${SSH_KEY}.pub" || {
    echo "ERROR: SSH public key not found: ${SSH_KEY}.pub"
    exit 1
}

test -f "$AUTHORIZED_KEYS_FILE" || {
    echo "ERROR: authorized keys file not found: $AUTHORIZED_KEYS_FILE"
    exit 1
}

# Read only valid SSH public-key lines.
mapfile -t PUBLIC_KEYS < <(
    grep -E '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) ' \
    "$AUTHORIZED_KEYS_FILE" || true
)

((${#PUBLIC_KEYS[@]} > 0)) || {
    echo "ERROR: no valid public keys found in $AUTHORIZED_KEYS_FILE"
    exit 1
}

# Derive the public key corresponding to the private key used
# for this deployment and make sure it is included.
DEPLOY_PUBLIC_KEY="$(cat "${SSH_KEY}.pub" | awk '{print $1" "$2}')"

KEY_FOUND=0
for key in "${PUBLIC_KEYS[@]}"; do
    key_no_comment="$(printf '%s\n' "$key" | awk '{print $1" "$2}')"
    if [[ "$key_no_comment" == "$DEPLOY_PUBLIC_KEY" ]]; then
        KEY_FOUND=1
        break
    fi
done

if [[ "$KEY_FOUND" -ne 1 ]]; then
    echo "ERROR: SSH private key does not match any public key"
    echo "       in AUTHORIZED_KEYS_FILE."
    echo "Refusing to change authorized_keys to avoid lockout."
    exit 1
fi

echo "[2/7] Testing SSH access to ${VM_USER}@${VM_HOST}:${VM_PORT}..."

ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    "echo 'SSH connection successful'"

echo "[3/7] Updating authorized_keys on the VM..."

# Replace the VM authorized_keys file with only the supplied
# group public keys. This removes the default student-admin key.
{
    printf '%s\n' "${PUBLIC_KEYS[@]}"
} | ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    'mkdir -p ~/.ssh &&
     chmod 700 ~/.ssh &&
     cat > ~/.ssh/authorized_keys &&
     chmod 600 ~/.ssh/authorized_keys'

echo "      authorized_keys updated."

echo "[4/7] Installing Python venv support if necessary..."

ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" <<'REMOTE_VENV'
if ! python3 -m venv /tmp/cs553_venv_test >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3.10-venv
fi
rm -rf /tmp/cs553_venv_test
REMOTE_VENV

echo "[5/7] Cloning/updating repository..."

ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    "REPO_URL='$REPO_URL' REPO_BRANCH='$REPO_BRANCH' DEPLOY_DIR='$DEPLOY_DIR' bash -s" <<'REMOTE_REPO'
set -euo pipefail

if [[ -d "$DEPLOY_DIR/.git" ]]; then
    cd "$DEPLOY_DIR"
    git fetch origin
    git checkout "$REPO_BRANCH"
    git reset --hard "origin/$REPO_BRANCH"
else
    rm -rf "$DEPLOY_DIR"
    git clone --branch "$REPO_BRANCH" "$REPO_URL" "$DEPLOY_DIR"
fi
REMOTE_REPO

echo "[6/7] Creating virtual environment and installing dependencies..."

ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    "DEPLOY_DIR='$DEPLOY_DIR' bash -s" <<'REMOTE_INSTALL'
set -euo pipefail

cd "$DEPLOY_DIR"

python3 -m venv .venv
source .venv/bin/activate

python -m pip install --upgrade pip
python -m pip install -r requirements.txt
REMOTE_INSTALL

echo "[7/7] Configuring StudyMate systemd service..."

ssh "${SSH_OPTS[@]}" \
    "${VM_USER}@${VM_HOST}" \
    "VM_USER='$VM_USER' DEPLOY_DIR='$DEPLOY_DIR' bash -s" <<'REMOTE_SERVICE'
set -euo pipefail

SERVICE_FILE="/etc/systemd/system/studymate.service"
ENV_DIR="/home/${VM_USER}/.config/studymate"
ENV_FILE="${ENV_DIR}/env"

sudo install -d -m 700 -o "$VM_USER" -g "$VM_USER" "$ENV_DIR"

# Optional Hugging Face environment file.
# The file is not required for local-model execution.
# It can be populated later without changing the service definition.
if [[ -f "$ENV_FILE" ]]; then
    sudo chmod 600 "$ENV_FILE"
fi

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=StudyMate AI Gradio Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${VM_USER}
WorkingDirectory=${DEPLOY_DIR}
Environment=PATH=${DEPLOY_DIR}/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
EnvironmentFile=-${ENV_FILE}
ExecStart=${DEPLOY_DIR}/.venv/bin/python ${DEPLOY_DIR}/app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable studymate.service
sudo systemctl restart studymate.service

sleep 3
sudo systemctl --no-pager --full status studymate.service
REMOTE_SERVICE

echo "      StudyMate systemd service configured."

echo "[7/7] Deployment complete."

echo
echo "Repository: $DEPLOY_DIR"
echo "Run the application with:"
echo "  cd $DEPLOY_DIR"
echo "  source .venv/bin/activate"
echo "  python app.py"
