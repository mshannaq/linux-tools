#!/bin/bash

# WHM API Token Security Review Script
# Purpose: Review WHM API tokens after a security incident or during routine audits.
# This script does not modify or delete anything.
# Author: Mohammed AlShannaq , MassarCloud Jordan
# @TODO Optimize

set -o pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root."
  echo "Please run it using root or sudo:"
  echo "sudo $0"
  exit 1
fi

REPORT_DATE="$(date '+%Y-%m-%d %H:%M:%S %Z')"
HOSTNAME_FQDN="$(hostname -f 2>/dev/null || hostname)"
CPANEL_VERSION="$(cat /usr/local/cpanel/version 2>/dev/null || /usr/local/cpanel/cpanel -V 2>/dev/null || echo 'Unknown')"

HIGH_RISK_ACLS=(
  "all"
  "create-acct"
  "edit-account"
  "create-user-session"
  "cpanel-api"
  "manage-api-tokens"
  "restart"
  "kill-acct"
  "suspend-acct"
  "passwd"
  "edit-dns"
  "manage-dns-records"
  "software-JetBackup5"
  "software-imunify360"
  "software-lvemanager"
)

echo "============================================================"
echo " WHM API Token Security Review"
echo "============================================================"
echo "Date:             ${REPORT_DATE}"
echo "Hostname:         ${HOSTNAME_FQDN}"
echo "cPanel Version:   ${CPANEL_VERSION}"
echo "============================================================"
echo

if ! command -v whmapi1 >/dev/null 2>&1; then
  echo "ERROR: whmapi1 command was not found."
  echo "This script must be run on a cPanel/WHM server."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 command was not found."
  echo "This script requires python3 to parse WHM API JSON output safely."
  exit 1
fi

TOKEN_JSON="$(whmapi1 api_token_list --output=json 2>/dev/null)"
WHMAPI_EXIT_CODE=$?

if [ "$WHMAPI_EXIT_CODE" -ne 0 ] || [ -z "$TOKEN_JSON" ]; then
  echo "ERROR: Failed to retrieve WHM API token list."
  exit 1
fi

export TOKEN_JSON
export HIGH_RISK_ACLS_JOINED="$(IFS=','; echo "${HIGH_RISK_ACLS[*]}")"

python3 <<'PY'
import os
import json
import datetime
import sys

raw_json = os.environ.get("TOKEN_JSON", "")
high_risk_acls = set(os.environ.get("HIGH_RISK_ACLS_JOINED", "").split(","))

try:
    payload = json.loads(raw_json)
except json.JSONDecodeError as exc:
    print(f"ERROR: Failed to parse WHM API JSON output: {exc}")
    sys.exit(1)

metadata = payload.get("metadata", {})
if metadata.get("result") != 1:
    print("ERROR: WHM API returned an unsuccessful result.")
    print(f"Reason: {metadata.get('reason', 'Unknown')}")
    sys.exit(1)

tokens = payload.get("data", {}).get("tokens", {})

if not tokens:
    print("Result: No WHM API tokens found.")
    print()
    print("Conclusion: PASS - No WHM API tokens exist on this server.")
    sys.exit(0)

total_tokens = len(tokens)
risky_tokens = []
review_tokens = []
known_dns_cluster_tokens = []

print(f"Total tokens found: {total_tokens}")
print()

for token_name, token_data in sorted(tokens.items()):
    acls = token_data.get("acls", {}) or {}
    enabled_acls = sorted([acl for acl, enabled in acls.items() if enabled == 1])
    risky_enabled_acls = sorted([acl for acl in enabled_acls if acl in high_risk_acls])

    create_time = token_data.get("create_time")
    expires_at = token_data.get("expires_at")

    if isinstance(create_time, int):
        created_readable = datetime.datetime.fromtimestamp(create_time).strftime("%Y-%m-%d %H:%M:%S")
    else:
        created_readable = "Unknown"

    if isinstance(expires_at, int):
        expires_readable = datetime.datetime.fromtimestamp(expires_at).strftime("%Y-%m-%d %H:%M:%S")
    elif expires_at is None:
        expires_readable = "Never / null"
    else:
        expires_readable = str(expires_at)

    is_reverse_trust = token_name.startswith("reverse_trust_")
    only_clustering = enabled_acls == ["clustering"]

    if is_reverse_trust and only_clustering:
        classification = "LIKELY LEGITIMATE - DNS Cluster / reverse trust"
        known_dns_cluster_tokens.append(token_name)
    elif risky_enabled_acls:
        classification = "HIGH REVIEW REQUIRED - High-risk ACL enabled"
        risky_tokens.append((token_name, risky_enabled_acls))
    else:
        classification = "REVIEW REQUIRED - Non-standard token"
        review_tokens.append(token_name)

    print("------------------------------------------------------------")
    print(f"Token name:      {token_name}")
    print(f"Created:         {created_readable}")
    print(f"Expires:         {expires_readable}")
    print(f"Enabled ACLs:    {', '.join(enabled_acls) if enabled_acls else 'None'}")
    print(f"Risky ACLs:      {', '.join(risky_enabled_acls) if risky_enabled_acls else 'None'}")
    print(f"Classification:  {classification}")

print("------------------------------------------------------------")
print()
print("Summary")
print("=======")
print(f"Total WHM API tokens:                    {total_tokens}")
print(f"Likely DNS Cluster reverse_trust tokens: {len(known_dns_cluster_tokens)}")
print(f"Tokens requiring review:                 {len(review_tokens)}")
print(f"Tokens with high-risk ACLs:              {len(risky_tokens)}")
print()

if known_dns_cluster_tokens:
    print("Likely DNS Cluster tokens:")
    for name in known_dns_cluster_tokens:
        print(f" - {name}")
    print()

if review_tokens:
    print("Tokens requiring manual review:")
    for name in review_tokens:
        print(f" - {name}")
    print()

if risky_tokens:
    print("High-risk tokens:")
    for name, risky_acls in risky_tokens:
        print(f" - {name}: {', '.join(risky_acls)}")
    print()

if risky_tokens:
    print("Conclusion: ATTENTION REQUIRED - One or more tokens have high-risk ACLs enabled.")
elif review_tokens:
    print("Conclusion: REVIEW REQUIRED - Tokens exist that are not recognised as DNS Cluster reverse_trust tokens.")
else:
    print("Conclusion: PASS - No suspicious WHM API token identified based on this review.")
PY

echo
echo "============================================================"
echo " Recommended next checks"
echo "============================================================"
echo "1) If any non-standard token appears, verify who created it and what system uses it."
echo "2) If a token has high-risk ACLs and is not required, revoke it after documenting it."
echo "3) reverse_trust_* tokens with only clustering=1 are usually related to DNS Cluster."
echo
echo "To revoke a suspicious token manually:"
echo "whmapi1 api_token_revoke token_name='TOKEN_NAME_HERE'"
echo "============================================================"
