#!/usr/bin/env bash

set -e

function die() {
    echo >&2 "$@"
    exit 1
}

function set_kubeconfig() {
   export KUBECONFIG="$(find . -name 'kubeconfig_*' -exec readlink -f {} \;)"
}

function get_aws_account_id() {
    echo "$(aws sts get-caller-identity --output text --query 'Account')"
}

function up() {
    echo "Bringing up your cluster! Go grab a coffee, you've earned it."
    echo "---------------------------------------------------------------"
    set -x

    # Run Terraform
    pushd terraform/
    terraform init
    terraform apply -auto-approve -var "account_id=$(get_aws_account_id)"
    popd

    set_kubeconfig

    # Install Tiller (use cluster-admin for now)
    helm init
    kubectl create serviceaccount --namespace kube-system tiller || true
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller || true
    kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'

    #  Give Tiller some time to restart
    sleep 20

    # Run Helmfile
    pushd helmfile/
    helmfile apply
    popd

    set +x
    echo "---------------------------------------------------------------"
    echo "Done!"
}

function down() {
    echo "Destroying your cluster! Bye bye bye - BYE BYE!"
    echo "---------------------------------------------------------------"
    set -x

    set_kubeconfig

    # Run Helmfile
    pushd helmfile/
    helmfile delete --purge || true
    popd

    # Uninstall Tiller
    helm list && helm reset --force || true

    # Run Terraform
    pushd terraform/
    terraform init
    terraform destroy -auto-approve -var "account_id=$(get_aws_account_id)"
    popd

    set +x
    echo "---------------------------------------------------------------"
    echo "Done!"
}

function main() {
    local action="$1"
    if [[ "$action" != "up" && "$action" != "down" ]]; then
        die "Error: first argument must be either 'up' or 'down'."
    fi

    if [[ ! -d "terraform" ]]; then
        die "missing terraform/ directory"
    fi

    if [[ ! -d "helmfile" ]]; then
        die "missing helmfile/ directory"
    fi

    ${action}
}

main "$@"

