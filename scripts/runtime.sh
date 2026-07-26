#!/usr/bin/env bash

set -Eeuo pipefail

action="${1:-}"
terraform_bin="${TERRAFORM:-terraform}"
terraform_dir="${TERRAFORM_DIR:-terraform}"
yc_bin="${YC:-yc}"
dry_run="${DRY_RUN:-0}"

kubernetes_name="${KUBERNETES_CLUSTER_NAME:-hexlet-5-cluster}"
node_group_name="${KUBERNETES_NODE_GROUP_NAME:-hexlet-5-workers}"
postgresql_name="${POSTGRESQL_CLUSTER_NAME:-hexlet-5-postgresql}"
load_balancer_name="${GWIN_LOAD_BALANCER_NAME:-gwin-ingress-group-hexlet-5-bulletin-board}"

kubernetes_id=""
kubernetes_status=""
node_group_id=""
node_group_status=""
postgresql_id=""
postgresql_status=""
load_balancer_id=""
load_balancer_status=""
folder_id=""

die() {
    printf 'runtime lifecycle: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 \
        || die "required command is not available: $1"
}

validate_name() {
    local label="$1"
    local value="$2"

    [[ "${#value}" -le 63 ]] \
        || die "$label is longer than 63 characters"
    [[ "$value" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] \
        || die "$label is not a valid exact resource name: $value"
}

validate_id() {
    local label="$1"
    local value="$2"

    [[ "$value" =~ ^[a-z0-9]{16,32}$ ]] \
        || die "$label is not a valid Yandex Cloud resource ID"
}

terraform_output() {
    local output_name="$1"
    local value

    if ! value="$(
        "$terraform_bin" -chdir="$terraform_dir" output -raw "$output_name"
    )"; then
        die "cannot read Terraform output $output_name"
    fi
    [[ -n "$value" ]] || die "Terraform output $output_name is empty"
    printf '%s' "$value"
}

terraform_json_output() {
    local output_name="$1"
    local value

    if ! value="$(
        "$terraform_bin" -chdir="$terraform_dir" output -json "$output_name"
    )"; then
        die "cannot read Terraform output $output_name"
    fi
    jq -e . >/dev/null <<<"$value" \
        || die "Terraform output $output_name is not valid JSON"
    printf '%s' "$value"
}

yc_json() {
    local output

    if ! output="$("$yc_bin" "$@" --format json)"; then
        die "read-only YC command failed: $*"
    fi
    jq -e . >/dev/null <<<"$output" \
        || die "YC returned invalid JSON for: $*"
    printf '%s' "$output"
}

json_string() {
    local json="$1"
    local filter="$2"
    local label="$3"
    local value

    if ! value="$(
        jq -er "$filter | select(type == \"string\" and length > 0)" \
            <<<"$json"
    )"; then
        die "JSON data has no valid $label"
    fi
    printf '%s' "$value"
}

verify_resource() {
    local json="$1"
    local expected_id="$2"
    local expected_name="$3"
    local expected_folder_id="${4:-}"
    local resource_label="$5"
    local actual_id
    local actual_name
    local actual_folder_id

    actual_id="$(json_string "$json" '.id' "$resource_label ID")"
    actual_name="$(json_string "$json" '.name' "$resource_label name")"
    actual_folder_id="$(
        json_string "$json" '.folder_id' "$resource_label folder ID"
    )"

    [[ "$actual_id" == "$expected_id" ]] \
        || die "$resource_label ID differs from exact discovery input"
    [[ "$actual_name" == "$expected_name" ]] \
        || die "$resource_label name is $actual_name, expected $expected_name"
    if [[ -n "$expected_folder_id" ]]; then
        [[ "$actual_folder_id" == "$expected_folder_id" ]] \
            || die "$resource_label belongs to another folder"
    fi
}

verify_node_group() {
    local json="$1"
    local actual_id
    local actual_name
    local actual_cluster_id

    actual_id="$(json_string "$json" '.id' 'node group ID')"
    actual_name="$(json_string "$json" '.name' 'node group name')"
    actual_cluster_id="$(
        json_string "$json" '.cluster_id' 'node group cluster ID'
    )"

    [[ "$actual_id" == "$node_group_id" ]] \
        || die "node group ID differs from exact Terraform output"
    [[ "$actual_name" == "$node_group_name" ]] \
        || die "node group name is $actual_name, expected $node_group_name"
    [[ "$actual_cluster_id" == "$kubernetes_id" ]] \
        || die "node group belongs to another Kubernetes cluster"
}

refresh_node_group_status() {
    local node_group_json

    node_group_json="$(
        yc_json managed-kubernetes node-group get --id "$node_group_id"
    )"
    verify_node_group "$node_group_json"
    node_group_status="$(
        json_string "$node_group_json" '.status' 'node group status'
    )"
}

discover_resources() {
    local kubernetes_json
    local node_group_output
    local postgresql_json
    local load_balancers_json
    local load_balancer_matches
    local load_balancer_json
    local match_count

    kubernetes_id="$(terraform_output kubernetes_cluster_id)"
    node_group_output="$(terraform_json_output kubernetes_node_group)"
    node_group_id="$(
        json_string "$node_group_output" '.id' 'Terraform node group ID'
    )"
    postgresql_id="$(terraform_output postgresql_cluster_id)"
    validate_id "Kubernetes cluster ID" "$kubernetes_id"
    validate_id "Kubernetes node group ID" "$node_group_id"
    validate_id "PostgreSQL cluster ID" "$postgresql_id"

    kubernetes_json="$(
        yc_json managed-kubernetes cluster get --id "$kubernetes_id"
    )"
    verify_resource \
        "$kubernetes_json" \
        "$kubernetes_id" \
        "$kubernetes_name" \
        "" \
        "Kubernetes cluster"
    folder_id="$(json_string "$kubernetes_json" '.folder_id' 'folder ID')"
    validate_id "folder ID" "$folder_id"
    kubernetes_status="$(
        json_string "$kubernetes_json" '.status' 'Kubernetes cluster status'
    )"

    refresh_node_group_status

    postgresql_json="$(
        yc_json managed-postgresql cluster get --id "$postgresql_id"
    )"
    verify_resource \
        "$postgresql_json" \
        "$postgresql_id" \
        "$postgresql_name" \
        "$folder_id" \
        "PostgreSQL cluster"
    postgresql_status="$(
        json_string "$postgresql_json" '.status' 'PostgreSQL cluster status'
    )"

    load_balancers_json="$(
        yc_json application-load-balancer load-balancer list \
            --folder-id "$folder_id"
    )"
    jq -e 'type == "array"' >/dev/null <<<"$load_balancers_json" \
        || die "YC load balancer list is not an array"
    load_balancer_matches="$(
        jq -c --arg expected_name "$load_balancer_name" \
            '[.[] | select(.name == $expected_name)]' \
            <<<"$load_balancers_json"
    )"
    match_count="$(jq -r 'length' <<<"$load_balancer_matches")"
    [[ "$match_count" == "1" ]] \
        || die "expected exactly one load balancer named $load_balancer_name in folder $folder_id, found $match_count"

    load_balancer_id="$(
        json_string "$load_balancer_matches" '.[0].id' 'load balancer ID'
    )"
    validate_id "load balancer ID" "$load_balancer_id"
    load_balancer_json="$(
        yc_json application-load-balancer load-balancer get \
            --id "$load_balancer_id"
    )"
    verify_resource \
        "$load_balancer_json" \
        "$load_balancer_id" \
        "$load_balancer_name" \
        "$folder_id" \
        "load balancer"
    load_balancer_status="$(
        json_string "$load_balancer_json" '.status' 'load balancer status'
    )"
}

print_status() {
    printf 'Kubernetes name=%s id=%s status=%s\n' \
        "$kubernetes_name" "$kubernetes_id" "$kubernetes_status"
    printf 'NodeGroup name=%s id=%s status=%s cluster_id=%s\n' \
        "$node_group_name" \
        "$node_group_id" \
        "$node_group_status" \
        "$kubernetes_id"
    printf 'PostgreSQL name=%s id=%s status=%s\n' \
        "$postgresql_name" "$postgresql_id" "$postgresql_status"
    printf 'LoadBalancer name=%s id=%s status=%s\n' \
        "$load_balancer_name" "$load_balancer_id" "$load_balancer_status"
}

is_running() {
    local resource_type="$1"
    local status="$2"

    case "$resource_type:$status" in
        kubernetes:RUNNING | node-group:RUNNING | postgresql:RUNNING | load-balancer:ACTIVE | load-balancer:RUNNING)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

validate_transition() {
    local transition="$1"
    local resource_type="$2"
    local resource_label="$3"
    local status="$4"

    case "$transition" in
        start)
            if is_running "$resource_type" "$status" || [[ "$status" == "STOPPED" ]]; then
                return
            fi
            ;;
        stop)
            if is_running "$resource_type" "$status" || [[ "$status" == "STOPPED" ]]; then
                return
            fi
            ;;
    esac
    die "$resource_label is in non-actionable status $status"
}

print_command() {
    printf 'DRY_RUN=1'
    printf ' %q' "$@"
    printf '\n'
}

run_mutation() {
    if [[ "$dry_run" == "1" ]]; then
        print_command "$@"
        return
    fi

    printf 'Executing:'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

start_resource() {
    local resource_type="$1"
    local resource_label="$2"
    local resource_id="$3"
    local status="$4"
    shift 4

    if is_running "$resource_type" "$status"; then
        printf '%s is already running; no action\n' "$resource_label"
        return
    fi
    run_mutation "$@" --id "$resource_id"
}

stop_resource() {
    local resource_type="$1"
    local resource_label="$2"
    local resource_id="$3"
    local status="$4"
    shift 4

    if [[ "$status" == "STOPPED" ]]; then
        printf '%s is already stopped; no action\n' "$resource_label"
        return
    fi
    run_mutation "$@" --id "$resource_id"
}

validate_kubernetes_pair() {
    if is_running kubernetes "$kubernetes_status"; then
        is_running node-group "$node_group_status" \
            || die "Kubernetes cluster is running but its exact node group is not"
    elif is_running node-group "$node_group_status"; then
        die "Kubernetes node group is running while its cluster is stopped"
    fi
}

gate_node_group_status() {
    local expected_status="$1"

    if [[ "$dry_run" == "1" ]]; then
        printf 'DRY_RUN=1 verify NodeGroup name=%s id=%s expected_status=%s after joint cluster lifecycle\n' \
            "$node_group_name" \
            "$node_group_id" \
            "$expected_status"
        return
    fi

    refresh_node_group_status
    [[ "$node_group_status" == "$expected_status" ]] \
        || die "node group status is $node_group_status, expected $expected_status"
}

validate_name "Kubernetes cluster name" "$kubernetes_name"
validate_name "Kubernetes node group name" "$node_group_name"
validate_name "PostgreSQL cluster name" "$postgresql_name"
validate_name "Gwin load balancer name" "$load_balancer_name"
[[ "$dry_run" == "0" || "$dry_run" == "1" ]] \
    || die "DRY_RUN must be exactly 0 or 1"

case "$action" in
    status | start | stop)
        ;;
    *)
        die "usage: scripts/runtime.sh status|start|stop"
        ;;
esac

require_command "$terraform_bin"
require_command "$yc_bin"
require_command jq

discover_resources
print_status

case "$action" in
    status)
        exit 0
        ;;
    start | stop)
        validate_transition "$action" kubernetes Kubernetes "$kubernetes_status"
        validate_transition "$action" node-group NodeGroup "$node_group_status"
        validate_transition "$action" postgresql PostgreSQL "$postgresql_status"
        validate_transition \
            "$action" \
            load-balancer \
            LoadBalancer \
            "$load_balancer_status"
        ;;
esac

validate_kubernetes_pair

if [[ "$action" == "start" ]] \
    && is_running load-balancer "$load_balancer_status" \
    && {
        ! is_running kubernetes "$kubernetes_status" \
            || ! is_running node-group "$node_group_status" \
            || ! is_running postgresql "$postgresql_status"
    }; then
    die "load balancer is running while a backend dependency is stopped"
fi

if [[ "$action" == "start" ]]; then
    start_resource \
        postgresql \
        PostgreSQL \
        "$postgresql_id" \
        "$postgresql_status" \
        "$yc_bin" managed-postgresql cluster start
    start_resource \
        kubernetes \
        Kubernetes \
        "$kubernetes_id" \
        "$kubernetes_status" \
        "$yc_bin" managed-kubernetes cluster start
    gate_node_group_status RUNNING
    start_resource \
        load-balancer \
        LoadBalancer \
        "$load_balancer_id" \
        "$load_balancer_status" \
        "$yc_bin" application-load-balancer load-balancer start
else
    stop_resource \
        load-balancer \
        LoadBalancer \
        "$load_balancer_id" \
        "$load_balancer_status" \
        "$yc_bin" application-load-balancer load-balancer stop
    stop_resource \
        kubernetes \
        Kubernetes \
        "$kubernetes_id" \
        "$kubernetes_status" \
        "$yc_bin" managed-kubernetes cluster stop
    gate_node_group_status STOPPED
    stop_resource \
        postgresql \
        PostgreSQL \
        "$postgresql_id" \
        "$postgresql_status" \
        "$yc_bin" managed-postgresql cluster stop
fi

if [[ "$dry_run" == "1" ]]; then
    printf 'Dry run complete; no resource state was changed.\n'
else
    discover_resources
    print_status
fi
