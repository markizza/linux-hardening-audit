#!/usr/bin/env bash

# SSH Hardening Audit
# Checks the effective OpenSSH configuration against defined security controls.
#
# Exit codes:
#   0 = all required controls passed
#   1 = one or more security controls failed
#   2 = the audit could not run correctly

set -u
set -o pipefail

PASS_COUNT=0
FAIL_COUNT=0
INFO_COUNT=0
SSHD_CONFIG=""

pass() {
    printf '[PASS] %s\n' "$1"
    ((PASS_COUNT += 1))
}

fail() {
    printf '[FAIL] %s\n' "$1"
    ((FAIL_COUNT += 1))
}

info() {
    printf '[INFO] %s\n' "$1"
    ((INFO_COUNT += 1))
}

error_exit() {
    printf '[ERROR] %s\n' "$1" >&2
    exit 2
}

check_requirements() {
    if ! command -v sshd >/dev/null 2>&1; then
        error_exit "sshd command not found."
    fi

    if [[ "$EUID" -ne 0 ]]; then
        error_exit "This audit must be run as root. Use: sudo $0"
    fi
}

validate_ssh_config() {
    if sshd -t; then
        pass "SSH configuration syntax is valid"
    else
        error_exit "SSH configuration syntax is invalid."
    fi
}

load_effective_config() {
    if ! SSHD_CONFIG="$(sshd -T 2>/dev/null)"; then
        error_exit "Unable to read effective SSH configuration."
    fi

    if [[ -z "$SSHD_CONFIG" ]]; then
        error_exit "Effective SSH configuration was empty."
    fi
}

get_value() {
    local key="$1"

    awk -v key="$key" '
        $1 == key {
            $1=""
            sub(/^[[:space:]]+/, "")
            print
            exit
        }
    ' <<< "$SSHD_CONFIG"
}

check_equals() {
    local key="$1"
    local expected="$2"
    local name="$3"
    local actual

    actual="$(get_value "$key")"

    if [[ -z "$actual" ]]; then
        fail "$name was not found"
    elif [[ "$actual" == "$expected" ]]; then
        pass "$name = $actual"
    else
        fail "$name = $actual (required: $expected)"
    fi
}

check_numeric_max() {
    local key="$1"
    local maximum="$2"
    local name="$3"
    local actual

    actual="$(get_value "$key")"

    if [[ ! "$actual" =~ ^[0-9]+$ ]]; then
        fail "$name has an unexpected value: ${actual:-not found}"
    elif (( actual <= maximum )); then
        pass "$name = $actual (required: <= $maximum)"
    else
        fail "$name = $actual (required: <= $maximum)"
    fi
}

check_allowed_user() {
    local required_user="$1"
    local actual
    local user

    actual="$(get_value "allowusers")"

    if [[ -z "$actual" ]]; then
        fail "AllowUsers is not configured"
        return
    fi

    for user in $actual; do
        if [[ "$user" == "$required_user" ]]; then
            pass "AllowUsers contains $required_user"
            return
        fi
    done

    fail "AllowUsers does not contain $required_user"
}

check_authorized_keys_command() {
    local configured

    configured="$(get_value "authorizedkeyscommand")"

    if [[ -z "$configured" ]]; then
        info "AuthorizedKeysCommand was not reported"
    else
        info "AuthorizedKeysCommand = $configured"
    fi

    if command -v ps >/dev/null 2>&1; then
        local runtime_args

        runtime_args="$(
            ps -eo args= |
            grep '[s]shd' |
            grep 'AuthorizedKeysCommand' |
            head -n 1 || true
        )"

        if [[ -n "$runtime_args" ]]; then
            info "Running sshd command line contains an AuthorizedKeysCommand override"
        else
            info "No AuthorizedKeysCommand override found in the running sshd command line"
        fi
    fi
}

run_checks() {
    check_equals "permitrootlogin" "no" "PermitRootLogin"
    check_equals "passwordauthentication" "no" "PasswordAuthentication"
    check_equals "kbdinteractiveauthentication" "no" "KbdInteractiveAuthentication"
    check_equals "pubkeyauthentication" "yes" "PubkeyAuthentication"

    check_allowed_user "ubuntu"

    check_numeric_max "maxauthtries" 3 "MaxAuthTries"
    check_numeric_max "logingracetime" 30 "LoginGraceTime"

    check_authorized_keys_command
}

show_summary() {
    printf '\n'
    printf '%s\n' "=== AUDIT SUMMARY ==="
    printf 'PASS: %d\n' "$PASS_COUNT"
    printf 'FAIL: %d\n' "$FAIL_COUNT"
    printf 'INFO: %d\n' "$INFO_COUNT"

    if (( FAIL_COUNT > 0 )); then
        printf '%s\n' "Result: FAILED"
        return 1
    fi

    printf '%s\n' "Result: PASSED"
    return 0
}

main() {
    printf '%s\n' "=== SSH HARDENING AUDIT ==="
    printf 'Host: %s\n' "$(hostname)"
    printf 'Time: %s\n' "$(date -Is)"
    printf '\n'

    check_requirements
    load_effective_config
    validate_ssh_config
    run_checks
    show_summary
}

main "$@"
