#!/usr/bin/env bash
# Mount TrueNAS (.111) Alfa-AI dataset at /mnt/cluster (NFS v4.1).
# Kept in sync with alfa-ai/scripts/mount_nfs_models.sh — same probe logic.
#
# Run on the Pi (or any Linux LAN host) before offline victron deploy:
#   sudo bash scripts/mount-truenas-hub.sh
#
# Env:
#   TRUENAS_IP   (default 192.168.0.111)
#   NFS_REMOTE   preferred export path (default /mnt/HDDs/Alfa-AI)
#   LOCAL_MOUNT  (default /mnt/cluster)
#
set -euo pipefail

TRUENAS_IP="${TRUENAS_IP:-192.168.0.111}"
NFS_REMOTE="${NFS_REMOTE:-/mnt/HDDs/Alfa-AI}"
LOCAL_MOUNT="${LOCAL_MOUNT:-/mnt/cluster}"

NFS_REMOTE_CANDIDATES=(
  "$NFS_REMOTE"
  "/mnt/HDDs/Alfa-AI"
  "/mnt/HDDs/alfa-ai-cluster"
)

echo "=== Mounting TrueNAS cluster hub share ==="
echo "Server: $TRUENAS_IP"
echo "Preferred remote path: $NFS_REMOTE"
echo "Local mount:  $LOCAL_MOUNT"
echo ""

if ! command -v mount.nfs &>/dev/null; then
  echo "Installing nfs-common..."
  sudo apt-get update -qq && sudo apt-get install -y -qq nfs-common
fi

sudo mkdir -p "$LOCAL_MOUNT"

if mountpoint -q "$LOCAL_MOUNT"; then
  echo "$LOCAL_MOUNT is already mounted:"
  findmnt "$LOCAL_MOUNT" || true
  exit 0
fi

SHOWMOUNT_OUT=""
if command -v showmount &>/dev/null; then
  SHOWMOUNT_OUT=$(showmount -e "$TRUENAS_IP" 2>&1 || true)
  if echo "$SHOWMOUNT_OUT" | grep -qF "$NFS_REMOTE"; then
    echo "showmount lists $NFS_REMOTE — good."
  elif echo "$SHOWMOUNT_OUT" | grep -q '/mnt/'; then
    echo "showmount export list (pick path in TrueNAS UI if mount fails):"
    echo "$SHOWMOUNT_OUT" | sed 's/^/  /'
  else
    echo "showmount empty or error (common on TrueNAS Scale). Will probe NFSv4.1 paths."
    echo "$SHOWMOUNT_OUT" | sed 's/^/  /'
  fi
else
  echo "showmount not found; probing paths."
fi
echo ""

declare -A seen=()
CAND_LIST=()
for p in "${NFS_REMOTE_CANDIDATES[@]}"; do
  [[ -z "$p" ]] && continue
  if [[ -z "${seen[$p]:-}" ]]; then
    seen[$p]=1
    CAND_LIST+=("$p")
  fi
done

PROBE_DIR=""
cleanup_probe() {
  if [[ -n "${PROBE_DIR:-}" ]] && [[ -d "$PROBE_DIR" ]]; then
    sudo umount -l "$PROBE_DIR" 2>/dev/null || true
    rmdir "$PROBE_DIR" 2>/dev/null || true
  fi
}
trap cleanup_probe EXIT

PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nfs-hub-probe.XXXXXX")
chmod 711 "$PROBE_DIR"

CHOSEN=""
for path in "${CAND_LIST[@]}"; do
  echo "Probing (read-only): ${TRUENAS_IP}:${path}"
  if sudo mount -t nfs -o vers=4.1,ro,soft,timeo=30 "$TRUENAS_IP:$path" "$PROBE_DIR" 2>/tmp/nfs-probe.err; then
    CHOSEN="$path"
    echo "  OK — NFS accepted this export path."
    sudo umount "$PROBE_DIR" || sudo umount -l "$PROBE_DIR" || true
    break
  else
    echo "  No: $(head -1 /tmp/nfs-probe.err 2>/dev/null || echo 'mount failed')"
  fi
done

if [[ -z "$CHOSEN" ]]; then
  echo ""
  echo "ERROR: Could not NFS-mount any ALFa hub candidate path from $TRUENAS_IP."
  if [[ -n "${SHOWMOUNT_OUT:-}" ]] && echo "$SHOWMOUNT_OUT" | grep -q '/mnt/'; then
    if ! echo "$SHOWMOUNT_OUT" | grep -qiE 'Alfa-AI|alfa-ai-cluster'; then
      echo ""
      echo "Exports exist but not the Alfa-AI hub dataset. Add NFS share path **/mnt/HDDs/Alfa-AI** on TrueNAS."
      echo "See alfa-ai docs: CLUSTER_SHARED_STORAGE.md §3."
    fi
  else
    echo "Fix on TrueNAS: **Shares → Unix Shares (NFS)** → path **/mnt/HDDs/Alfa-AI**"
  fi
  exit 1
fi

NFS_REMOTE="$CHOSEN"
echo ""
echo "Mounting read-write: ${TRUENAS_IP}:${NFS_REMOTE} -> $LOCAL_MOUNT"
sudo mount -t nfs -o vers=4.1,soft,timeo=600 "$TRUENAS_IP:$NFS_REMOTE" "$LOCAL_MOUNT"
echo "Mounted."
trap - EXIT
cleanup_probe

FSTAB_ENTRY="$TRUENAS_IP:$NFS_REMOTE $LOCAL_MOUNT nfs vers=4.1,_netdev,x-systemd.automount 0 0"
if ! grep -qF "$TRUENAS_IP:$NFS_REMOTE $LOCAL_MOUNT" /etc/fstab 2>/dev/null; then
  echo "Adding to /etc/fstab..."
  echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
else
  echo "fstab entry already present for this server+path+mountpoint."
fi

echo ""
echo "=== Mount Complete ==="
echo "Victron offline wheels:  $LOCAL_MOUNT/wheels/victron/"
echo "HA docker-load tarball: $LOCAL_MOUNT/docker-images/home-assistant-2026.7.3.tar.gz (or legacy home-assistant-stable.tar.gz)"
echo "Docker Hub mirror:       ${TRUENAS_IP}:5000 (merged into daemon.json by deploy.sh)"
