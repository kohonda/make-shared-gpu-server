#!/usr/bin/env bash
#
# Write the admin's notes to the Desktop of the admin who runs this script.
#   sudo ./scripts/update-admin-notes.sh
#
# Creates <Desktop>/server-admin-notes/{admin.txt,users.txt}. Each run rebuilds
# only the part above the marker line, so what the admin wrote below it stays.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ---------- configurable variables ----------
SHARED_GROUP="${SHARED_GROUP:-labmembers}"
# --------------------------------------------

SUDO_GROUP="sudo"
NOTES_DIR_NAME="server-admin-notes"
TMP_PREFIX=".update-tmp"
MONITORING_ENV_FILE="$REPO_ROOT/config/monitoring/.env"
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
TAILSCALE_ADMIN_URL="https://login.tailscale.com/admin/machines"
UNSET_LABEL="未設定"
MANUAL_MARKER="===== ここから下は手書き（更新しても消えません） ====="

ADMIN_MANUAL_TEMPLATE='
鍵の実際の値はパスワードマネージャーに置き、ここには用途、保管場所、再発行手順だけを書きます。
このメモはサーバーと一緒に失われ、docker グループの利用者にも読めるためです。

[Tailscale 認証キー]
  用途:
  保管場所:
  再発行手順:

[GitHub トークン]
  用途:
  保管場所:
  再発行手順:

[sudo パスワード]
  用途:
  保管場所:
  再発行手順:'

USERS_MANUAL_TEMPLATE='
ユーザーごとに次のブロックを書き足します。

[ユーザー名]
  本名:
  Tailscale のメールアドレス:
  追加日:'

tailscale_ipv4() {
    tailscale ip -4 2>/dev/null | head -n1 || true   # Tailscale may be absent or stopped
}

tailscale_fqdn() {
    tailscale status --json 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Self",{}).get("DNSName","").rstrip("."))' \
        2>/dev/null || true   # Tailscale may be absent or stopped
}

# Read one value without sourcing .env: root must not execute a file's contents
# just to read a password. Compose lets the last line win and strips outer quotes.
read_monitoring_env_value() {
    local key="$1"
    [[ -r "$MONITORING_ENV_FILE" ]] || return 0
    sed -n "s/^${key}=//p" "$MONITORING_ENV_FILE" | tail -n1 \
        | sed -E "s/\r$//; s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

ssh_command() {
    local user="$1" ssh_host="$2"
    if [[ -z "$ssh_host" ]]; then
        printf '%s\n' "$UNSET_LABEL"
        return 0
    fi
    printf 'ssh %s@%s\n' "$user" "$ssh_host"
}

# The URL needs both the Tailscale IP the stack binds to and the .env that configures it.
monitoring_url() {
    local tailscale_ip="$1" port="$2"
    if [[ -z "$tailscale_ip" || ! -f "$MONITORING_ENV_FILE" ]]; then
        printf '%s\n' "$UNSET_LABEL"
        return 0
    fi
    printf 'http://%s:%s\n' "$tailscale_ip" "$port"
}

render_connection_section() {
    local fqdn="$1" tailscale_ip="$2" admin_user="$3"
    cat <<EOF
[サーバー接続]
  ホスト名: $(hostname)
  FQDN: ${fqdn:-$UNSET_LABEL}
  Tailscale IP: ${tailscale_ip:-$UNSET_LABEL}
  管理者の ssh: $(ssh_command "$admin_user" "${fqdn:-$tailscale_ip}")
  Tailscale 管理画面: $TAILSCALE_ADMIN_URL
EOF
}

render_monitoring_section() {
    local tailscale_ip="$1" grafana_user grafana_password
    grafana_user=$(read_monitoring_env_value GF_SECURITY_ADMIN_USER)
    grafana_password=$(read_monitoring_env_value GF_SECURITY_ADMIN_PASSWORD)
    cat <<EOF
[監視]
  Grafana: $(monitoring_url "$tailscale_ip" "$GRAFANA_PORT")
  Grafana のユーザー: ${grafana_user:-$UNSET_LABEL}
  Grafana のパスワード: ${grafana_password:-$UNSET_LABEL}
  Prometheus: $(monitoring_url "$tailscale_ip" "$PROMETHEUS_PORT")
EOF
}

render_commands_section() {
    cat <<EOF
[コマンド]
  Tailscale の状態: tailscale status
  GPU の状態: nvidia-smi
  監視スタックの状態: cd $REPO_ROOT/config/monitoring && sudo docker compose ps
  このメモの更新: sudo $SCRIPT_DIR/update-admin-notes.sh
EOF
}

render_admin_auto_section() {
    local fqdn="$1" tailscale_ip="$2" admin_user="$3"
    render_connection_section "$fqdn" "$tailscale_ip" "$admin_user"
    printf '\n'
    render_monitoring_section "$tailscale_ip"
    printf '\n'
    render_commands_section
}

# Print a group's members, including users who have it only as their primary group,
# which the member field of the group entry does not list.
list_group_members() {
    local group="$1" gid
    gid=$(getent group "$group" | cut -d: -f3) || true
    [[ -n "$gid" ]] || return 0
    getent group "$group" | cut -d: -f4 | tr ',' '\n'
    getent passwd | awk -F: -v gid="$gid" '$4 == gid { print $1 }'
}

render_user_entry() {
    local user="$1" ssh_host="$2" passwd_entry
    passwd_entry=$(getent passwd "$user") || return 0
    cat <<EOF
[$user]
  UID: $(cut -d: -f3 <<<"$passwd_entry")
  グループ: $(id -nG "$user")
  ホーム: $(cut -d: -f6 <<<"$passwd_entry")
  ssh: $(ssh_command "$user" "$ssh_host")

EOF
}

render_users_auto_section() {
    local ssh_host="$1" user
    { list_group_members "$SHARED_GROUP"; list_group_members "$SUDO_GROUP"; } \
        | sed '/^$/d' | sort -u \
        | while IFS= read -r user; do
            render_user_entry "$user" "$ssh_host"
        done
}

resolve_desktop_dir() {
    local user="$1" home="$2" desktop
    desktop=$(sudo -H -u "$user" xdg-user-dir DESKTOP 2>/dev/null) || true
    desktop="${desktop%/}"
    # xdg-user-dir answers $HOME when the user has disabled the Desktop directory.
    if [[ "$desktop" != /* || "$desktop" == "$home" ]]; then
        desktop="$home/Desktop"
    fi
    printf '%s\n' "$desktop"
}

refuse_unsafe_note_path() {
    local path="$1"
    [[ ! -L "$path" ]] || die "Refusing to write through a symbolic link: $path"
    [[ ! -e "$path" || -f "$path" ]] || die "Not a regular file: $path"
}

# The admin creates the directory, so parents get the admin as owner and root
# cannot be steered into a location the admin could not write to anyway.
prepare_notes_dir() {
    local notes_dir="$1" user="$2" group="$3"
    [[ ! -L "$notes_dir" ]] || die "Refusing to write through a symbolic link: $notes_dir"
    sudo -H -u "$user" mkdir -p -- "$notes_dir" || die "Cannot create directory: $notes_dir"
    chown -- "$user:$group" "$notes_dir"
    chmod 700 -- "$notes_dir"
}

print_manual_section() {
    local path="$1" template="$2"
    if [[ ! -e "$path" ]]; then
        printf '%s\n' "$template"
        return 0
    fi
    awk -v marker="$MANUAL_MARKER" 'in_manual { print } $0 == marker { in_manual = 1 }' "$path"
}

write_note() {
    local path="$1" auto_section="$2" manual_template="$3" owner="$4" tmp_file
    if [[ -e "$path" ]] && ! grep -qFx -- "$MANUAL_MARKER" "$path"; then
        log_warn "Marker line not found, leaving the file unchanged: $path"
        return 0
    fi
    tmp_file=$(mktemp "$(dirname "$path")/$TMP_PREFIX.XXXXXX")
    {
        printf '%s\n\n%s\n' "$auto_section" "$MANUAL_MARKER"
        print_manual_section "$path" "$manual_template"
    } >"$tmp_file"
    chown -- "$owner" "$tmp_file"
    chmod 600 -- "$tmp_file"
    mv -fT -- "$tmp_file" "$path"
    log_info "Updated: $path"
}

require_root

if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
    die "Run this through sudo from the admin account (the notes go on that account's Desktop)."
fi
ADMIN_USER="$SUDO_USER"
ADMIN_GROUP=$(id -gn "$ADMIN_USER")
ADMIN_HOME=$(getent passwd "$ADMIN_USER" | cut -d: -f6)
[[ -n "$ADMIN_HOME" ]] || die "Home directory not found for: $ADMIN_USER"

NOTES_DIR="$(resolve_desktop_dir "$ADMIN_USER" "$ADMIN_HOME")/$NOTES_DIR_NAME"
ADMIN_NOTE="$NOTES_DIR/admin.txt"
USERS_NOTE="$NOTES_DIR/users.txt"
trap 'rm -f -- "$NOTES_DIR/$TMP_PREFIX".*' EXIT

prepare_notes_dir "$NOTES_DIR" "$ADMIN_USER" "$ADMIN_GROUP"
refuse_unsafe_note_path "$ADMIN_NOTE"
refuse_unsafe_note_path "$USERS_NOTE"

TAILSCALE_IP=$(tailscale_ipv4)
TAILSCALE_FQDN=$(tailscale_fqdn)
ADMIN_AUTO_SECTION=$(render_admin_auto_section "$TAILSCALE_FQDN" "$TAILSCALE_IP" "$ADMIN_USER")
USERS_AUTO_SECTION=$(render_users_auto_section "${TAILSCALE_FQDN:-$TAILSCALE_IP}")

write_note "$ADMIN_NOTE" "$ADMIN_AUTO_SECTION" "$ADMIN_MANUAL_TEMPLATE" "$ADMIN_USER:$ADMIN_GROUP"
write_note "$USERS_NOTE" "$USERS_AUTO_SECTION" "$USERS_MANUAL_TEMPLATE" "$ADMIN_USER:$ADMIN_GROUP"
