#!/usr/bin/env bash
#
# dovecot_failed_login_check.sh
#
# Purpose:
#   - Inspect Dovecot "auth failed" events for a chosen time window (in minutes),
#     then list the top offending IPs and optionally block selected IPs.
#
# How it works:
#   1) Asks for:
#        - Time window in minutes (default: 60)
#        - Minimum failed attempts to prompt for blocking (default: 10)
#   2) Collects failed login IPs from:
#        - systemd journal (journalctl -u dovecot) if available,
#        - otherwise falls back to /var/log/maillog (common on cPanel servers).
#   3) Shows top IPs (count + IP) that meet the minimum threshold.
#   4) Prompts per IP to block it for 2 days.
#   5) Writes an audit log to: /var/log/dovecot-faild-login-check.log
#
# Requirements / Assumptions:
#   - Must be executed as root (required to run Imunify360 CLI and read logs).
#   - The server is expected to have Imunify360 installed, and the command
#     "imunify360-agent" must be available in PATH.
#
# Optional:
#   --dry-run  : Perform all checks and prompts, but do NOT apply actual blocks.
#

set -euo pipefail

LOG_FILE="/var/log/dovecot-faild-login-check.log"
DEFAULT_MINUTES=60
DEFAULT_MIN_FAILS=10
TOP_N=30
TAIL_LINES=200000
echo ""
echo "Check Dovecot failed login attempts and block suspected IP after Confirm"
echo ""
echo "You can use with  --dry-run parameter to just dry run without real block"
echo ""

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--dry-run]"
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

if ! command -v imunify360-agent >/dev/null 2>&1; then
  echo "ERROR: imunify360-agent not found. Is Imunify360 installed?"
  exit 1
fi

timestamp() { date '+%F %T'; }

log() {
  local msg="$*"
  echo "$(timestamp) ${msg}" >> "${LOG_FILE}"
}

read -r -p "How many minutes to check? [${DEFAULT_MINUTES}]: " MINUTES_INPUT
MINUTES_INPUT="${MINUTES_INPUT:-$DEFAULT_MINUTES}"

if ! [[ "${MINUTES_INPUT}" =~ ^[0-9]+$ ]] || [[ "${MINUTES_INPUT}" -le 0 ]]; then
  echo "ERROR: Minutes must be a positive integer."
  exit 1
fi

read -r -p "Minimum failed attempts to consider blocking? [${DEFAULT_MIN_FAILS}]: " MIN_FAILS_INPUT
MIN_FAILS_INPUT="${MIN_FAILS_INPUT:-$DEFAULT_MIN_FAILS}"

if ! [[ "${MIN_FAILS_INPUT}" =~ ^[0-9]+$ ]] || [[ "${MIN_FAILS_INPUT}" -le 0 ]]; then
  echo "ERROR: Minimum failed attempts must be a positive integer."
  exit 1
fi

MINUTES="${MINUTES_INPUT}"
MIN_FAILS="${MIN_FAILS_INPUT}"

SINCE_EPOCH="$(date -d "${MINUTES} minutes ago" '+%s' 2>/dev/null || true)"
EXPIRATION_EPOCH="$(date -d "2 days" '+%s')"

echo
echo "Checking Dovecot auth failed IPs for the last ${MINUTES} minutes..."
echo "Minimum fails to prompt: ${MIN_FAILS}"
echo "Log: ${LOG_FILE}"
echo "Dry-run: $([[ "${DRY_RUN}" -eq 1 ]] && echo "YES" || echo "NO")"
echo

get_ips_from_journal() {
  journalctl -u dovecot --since "${MINUTES} minutes ago" --no-pager 2>/dev/null \
  | grep -i "auth failed" \
  | sed -n 's/.*rip=\([^, ]*\).*/\1/p' \
  | sort | uniq -c | sort -nr | head -n "${TOP_N}" || true
}

get_ips_from_maillog() {
  if [[ -z "${SINCE_EPOCH}" ]]; then
    return 0
  fi

  [[ -f /var/log/maillog ]] || return 0

  tail -n "${TAIL_LINES}" /var/log/maillog \
  | gawk -v start="${SINCE_EPOCH}" '
      BEGIN{
        split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ");
        for(i=1;i<=12;i++) mon[m[i]]=i;
        year=strftime("%Y");
      }
      {
        # Syslog format: "Jan  5 12:34:56 host ..."
        mo=$1; da=$2; tm=$3;
        if(!(mo in mon)) next;
        split(tm, t, ":");
        if(length(t)!=3) next;
        ts=mktime(year " " mon[mo] " " da " " t[1] " " t[2] " " t[3]);
        if(ts < start) next;

        line=tolower($0);
        if(index(line, "dovecot") == 0) next;
        if(index(line, "auth failed") == 0) next;

        if (match($0, /rip=([^, ]+)/, a)) {
          ip=a[1];
          if(ip != "") cnt[ip]++;
        }
      }
      END{
        for(ip in cnt) printf "%8d %s\n", cnt[ip], ip;
      }
    ' 2>/dev/null \
  | sort -nr | head -n "${TOP_N}" || true
}

filter_results_by_min_fails() {
  # Input lines: "<count> <ip>"
  awk -v min="${MIN_FAILS}" '
    $1 ~ /^[0-9]+$/ && $1 >= min && $2 != "" { print $1, $2 }
  '
}

RESULTS="$(get_ips_from_journal | filter_results_by_min_fails)"
SOURCE="journalctl"

if [[ -z "${RESULTS// /}" ]]; then
  RESULTS="$(get_ips_from_maillog | filter_results_by_min_fails)"
  SOURCE="maillog"
fi

if [[ -z "${RESULTS// /}" ]]; then
  echo "No IPs reached ${MIN_FAILS}+ failed attempts in the last ${MINUTES} minutes."
  log "No IPs reached min_fails=${MIN_FAILS} in last ${MINUTES} minutes."
  exit 0
fi

echo "Source: ${SOURCE}"
echo "IPs with ${MIN_FAILS}+ failed logins (count ip):"
echo "${RESULTS}"
echo

log "Run started: minutes=${MINUTES}, min_fails=${MIN_FAILS}, source=${SOURCE}, dry_run=${DRY_RUN}"
log "Results:"
while read -r line; do
  [[ -n "${line// /}" ]] || continue
  log "  ${line}"
done <<< "${RESULTS}"

# Fix interactive prompt bug:
# Read RESULTS into an array first, then prompt via /dev/tty so user can answer.
mapfile -t RESULT_LINES <<< "${RESULTS}"

for line in "${RESULT_LINES[@]}"; do
  [[ -n "${line// /}" ]] || continue

  count="$(awk '{print $1}' <<< "$line")"
  ip="$(awk '{print $2}' <<< "$line")"

  if [[ -z "${ip}" ]]; then
    continue
  fi

  echo
  echo "IP: ${ip} | Failed attempts: ${count} (last ${MINUTES} minutes)"

  ans=""
  if [[ -e /dev/tty ]]; then
    read -r -p "Block this IP for 2 days via Imunify360? [y/N]: " ans < /dev/tty || ans=""
  else
    echo "WARNING: /dev/tty not available; cannot prompt. Skipping ${ip}."
    log "WARNING: /dev/tty not available; skipped ip=${ip} (count=${count})"
    continue
  fi

  if [[ "${ans}" =~ ^[Yy]$ ]]; then
    COMMENT="Dovecot failed login (${count} fails in last ${MINUTES}m)"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[DRY-RUN] Would run:"
      echo "imunify360-agent ip-list local add --purpose drop ${ip} --expiration ${EXPIRATION_EPOCH} --comment \"${COMMENT}\""
      log "[DRY-RUN] Would block ip=${ip} expiration=${EXPIRATION_EPOCH} comment='${COMMENT}'"
    else
      if imunify360-agent ip-list local add --purpose drop "${ip}" --expiration "${EXPIRATION_EPOCH}" --comment "${COMMENT}" >/dev/null 2>&1; then
        echo "OK: Blocked ${ip} (expires in 2 days)."
        log "Blocked ip=${ip} expiration=${EXPIRATION_EPOCH} comment='${COMMENT}'"
      else
        echo "ERROR: Failed to block ${ip} via imunify360-agent."
        log "ERROR blocking ip=${ip}"
      fi
    fi
  else
    echo "Skipped ${ip}."
    log "Skipped ip=${ip} (count=${count})"
  fi
done

echo
echo "Done."
log "Run finished."
