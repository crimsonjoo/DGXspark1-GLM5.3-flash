#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; CONFIG_FILE="${CONFIG_FILE:-$ROOT/.env.glm}"; CHECK=0
usage(){ echo 'Usage: ./start.sh [--check] [--config PATH]'; }
while [ "$#" -gt 0 ]; do case "$1" in --check) CHECK=1; shift;; --config) [ "$#" -ge 2 ] || exit 2; CONFIG_FILE="$2"; shift 2;; -h|--help) usage; exit;; *) usage >&2; exit 2;; esac; done
log(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }; ok(){ printf '\033[1;32m  OK\033[0m  %s\n' "$*"; }; warn(){ printf '\033[1;33m  WARN\033[0m  %s\n' "$*" >&2; }; die(){ printf '\033[1;31m  ERROR\033[0m %s\n' "$*" >&2; exit 1; }
if [ ! -e "$CONFIG_FILE" ] && [ "$CHECK" = 0 ]; then cp "$ROOT/.env.glm.example" "$CONFIG_FILE"; chmod 600 "$CONFIG_FILE"; ok "Created $CONFIG_FILE"; fi
if [ -f "$CONFIG_FILE" ]; then set -a; source "$CONFIG_FILE"; set +a; fi
PORT="${PORT:-18080}"; BACKEND_PORT="${BACKEND_PORT:-18081}"; MODEL_NAME="${MODEL_NAME:-GLM-5.3-Flash-EXL3-2.05}"; MODEL_DIR="${MODEL_DIR:-$HOME/models/GLM-5.3-Flash-exl3-2.05bpw}"; DFLASH_DIR="${DFLASH_DIR:-$HOME/models/GLM-5.3-Flash-DFlash2}"; CACHE_ROOT="${CACHE_ROOT:-$HOME/.cache/glm53-one-spark}"
IMAGE="${IMAGE:-glm53-one-spark:safe-sm121}"; BASE_IMAGE="${BASE_IMAGE:-ghcr.io/gitcommit90/glm-5.3-one-spark:general23}"; DOCKERFILE="${DOCKERFILE:-Dockerfile.safe}"; BUILD_IMAGE="${BUILD_IMAGE:-1}"; FORCE_BUILD="${FORCE_BUILD:-0}"; ACCEPT_DFLASH2_NC_LICENSE="${ACCEPT_DFLASH2_NC_LICENSE:-0}"; SSH_USER="${SSH_USER:-sejin}"; CONFIGURE_SSH="${CONFIGURE_SSH:-1}"; RESET_SSH_PASSWORD="${RESET_SSH_PASSWORD:-0}"
CTX="${CTX:-262144}"; SEQS="${SEQS:-4}"; GPU_MEM="${GPU_MEM:-0.90}"; MAX_BATCHED_TOKENS="${MAX_BATCHED_TOKENS:-7168}"; K="${K:-5}"; WATCHDOG="${WATCHDOG:-1}"; READY_TIMEOUT="${READY_TIMEOUT:-1200}"
for x in PORT BACKEND_PORT CTX SEQS MAX_BATCHED_TOKENS K READY_TIMEOUT; do [[ "${!x}" =~ ^[0-9]+$ ]] || die "Invalid $x=${!x}"; done; [ "$PORT" -le 65535 ] || die 'PORT out of range'; [ -f "$ROOT/$DOCKERFILE" ] || die "Dockerfile missing: $DOCKERFILE"
as_root(){ if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }; need_sudo(){ [ "$(id -u)" = 0 ] || { command -v sudo >/dev/null || die 'sudo is required'; sudo -v || die 'sudo authorization failed'; }; }
base_packages(){ command -v apt-get >/dev/null || die 'Automatic provisioning supports apt-based DGX OS'; need_sudo; as_root apt-get update; as_root apt-get install -y --no-install-recommends ca-certificates curl gnupg git openssh-server iproute2 python3 python3-venv; }
install_docker(){ log 'Installing Docker'; base_packages; . /etc/os-release; local d="${ID:-ubuntu}" c="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"; case "$d" in ubuntu|debian);; *) die "Unsupported distro $d";; esac; as_root install -m 0755 -d /etc/apt/keyrings; as_root curl -fsSL "https://download.docker.com/linux/$d/gpg" -o /etc/apt/keyrings/docker.asc; as_root chmod a+r /etc/apt/keyrings/docker.asc; printf 'Types: deb\nURIs: https://download.docker.com/linux/%s\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' "$d" "$c" "$(dpkg --print-architecture)" | as_root tee /etc/apt/sources.list.d/docker.sources >/dev/null; as_root apt-get update; as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; as_root systemctl enable --now docker; }
docker_access(){ docker info >/dev/null 2>&1 && return; need_sudo; if as_root docker info >/dev/null 2>&1; then local u="${SUDO_USER:-$(id -un)}"; as_root usermod -aG docker "$u"; ok "Added $u to docker group; restarting this script"; exec sg docker -c "$(printf '%q ' "$ROOT/start.sh" --config "$CONFIG_FILE")"; fi; die 'Docker daemon unavailable'; }
install_toolkit(){ log 'Installing NVIDIA Container Toolkit'; base_packages; as_root install -m 0755 -d /usr/share/keyrings; curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | as_root gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg; curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | as_root tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null; as_root apt-get update; as_root apt-get install -y nvidia-container-toolkit; as_root nvidia-ctk runtime configure --runtime=docker; as_root systemctl restart docker; }
setup_ssh(){
  [ "$CONFIGURE_SSH" = 1 ] || return 0
  log 'Checking SSH'
  local managed=/etc/ssh/sshd_config.d/90-glm53-bootstrap.conf
  if command -v sshd >/dev/null && id "$SSH_USER" >/dev/null 2>&1 && systemctl is-active --quiet ssh 2>/dev/null && [ "$RESET_SSH_PASSWORD" != 1 ]; then
    ok "SSH already active for $SSH_USER"; return
  fi
  command -v sshd >/dev/null || base_packages
  need_sudo
  id "$SSH_USER" >/dev/null 2>&1 || { as_root useradd --create-home --shell /bin/bash "$SSH_USER"; ok "Created user $SSH_USER"; }
  local state; state="$(as_root passwd -S "$SSH_USER" 2>/dev/null | awk '{print $2}')"
  if [ "$RESET_SSH_PASSWORD" = 1 ] || [ "$state" = L ] || [ "$state" = NP ] || [ -z "$state" ]; then
    [ -t 0 ] || die "$SSH_USER needs a password; rerun interactively"
    as_root passwd "$SSH_USER"
  fi
  printf '%s\n' '# Managed by DGXspark1-GLM5.3-flash/start.sh' 'PasswordAuthentication yes' 'PubkeyAuthentication yes' 'PermitRootLogin no' | as_root tee "$managed" >/dev/null
  as_root sshd -t; as_root systemctl enable --now ssh; as_root systemctl reload ssh
  if command -v ufw >/dev/null && as_root ufw status | grep -q '^Status: active'; then as_root ufw allow 22/tcp >/dev/null; as_root ufw allow "$PORT/tcp" >/dev/null; fi
  ok "SSH ready for $SSH_USER"
}
log 'DGX Spark preflight'; command -v nvidia-smi >/dev/null || die 'NVIDIA driver missing; repair DGX OS/driver first'; nvidia-smi --query-gpu=name,driver_version --format=csv,noheader || die 'nvidia-smi failed'; [ "$(uname -m)" = aarch64 ] || warn "Expected aarch64, found $(uname -m)"
if [ "$CHECK" = 1 ]; then command -v docker >/dev/null && ok 'Docker installed' || warn 'Docker missing'; docker info >/dev/null 2>&1 && ok 'Docker accessible' || warn 'Docker inaccessible'; [ -f "$MODEL_DIR/config.json" ] && ok 'Target model present' || warn 'Target model missing'; [ -f "$DFLASH_DIR/config.json" ] && ok 'DFlash2 present' || warn 'DFlash2 missing'; exit; fi
command -v curl >/dev/null && command -v python3 >/dev/null || base_packages; command -v docker >/dev/null || install_docker; docker_access
if ! command -v nvidia-ctk >/dev/null 2>&1 || ! nvidia-ctk cdi list 2>/dev/null | grep -q 'nvidia.com/gpu=all'; then install_toolkit; fi
docker_access; setup_ssh
if [ "$ACCEPT_DFLASH2_NC_LICENSE" != 1 ]; then printf '\nDFlash2: CC BY-NC-ND 4.0, non-commercial research/evaluation.\nhttps://huggingface.co/incoai/GLM-5.3-Flash-DFlash2\n'; [ -t 0 ] || die 'Set ACCEPT_DFLASH2_NC_LICENSE=1 in .env.glm after accepting'; read -r -p 'Accept? [y/N] ' answer; [[ "$answer" =~ ^[Yy]$ ]] || die 'License not accepted'; sed -i 's/^ACCEPT_DFLASH2_NC_LICENSE=.*/ACCEPT_DFLASH2_NC_LICENSE=1/' "$CONFIG_FILE"; ACCEPT_DFLASH2_NC_LICENSE=1; export ACCEPT_DFLASH2_NC_LICENSE; fi
mkdir -p "$MODEL_DIR" "$DFLASH_DIR" "$CACHE_ROOT"; avail="$(df -Pk "$MODEL_DIR" | awk 'NR==2{print $4}')"; [ "$avail" -ge $((100*1024*1024)) ] || warn 'Less than 100 GiB free; fresh install may fail'
if [ ! -f "$MODEL_DIR/config.json" ] || [ ! -f "$MODEL_DIR/model.safetensors.index.json" ] || [ ! -f "$DFLASH_DIR/config.json" ]; then log 'Downloading pinned models'; MODEL_DIR="$MODEL_DIR" DFLASH_DIR="$DFLASH_DIR" ACCEPT_DFLASH2_NC_LICENSE=1 "$ROOT/download.sh"; else ok 'Model files already exist'; fi
log 'Preparing runtime image'; if [ "$BUILD_IMAGE" = 1 ]; then if [ "$FORCE_BUILD" = 1 ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then docker build --progress=plain -f "$ROOT/$DOCKERFILE" --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg GLM53_RECIPE_STAMP=tp1-general23-exl3-mul1-fused -t "$IMAGE" "$ROOT"; else ok "Image $IMAGE exists"; fi; else docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull "$IMAGE"; fi
CONFIG_ALREADY_LOADED=1 CONFIG_FILE="$CONFIG_FILE" "$ROOT/apply.sh"
