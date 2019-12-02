#!/usr/bin/env bash
set -euo pipefail

NSC_DIR=${DEFAULT_NSC_DIR:=$(pwd)/nsc}
SKIP_NSC_DIR_CHOWN=${DEFAULT_SKIP_NSC_DIR_CHOWN:=false}

export NATS_CONFIG_HOME=$NSC_DIR/config
export NKEYS_PATH=$NSC_DIR/nkeys
export NSC_HOME=$NSC_DIR/accounts

create_creds() {
	mkdir -p "$NKEYS_PATH"
	mkdir -p "$NSC_HOME"
	mkdir -p "$NATS_CONFIG_HOME"

	nsc add operator --name KO

	# Create system account
	nsc add account --name SYS
	nsc add user --name sys

	# Create a couple of accounts (A & B) for testing purposes.
	nsc add account --name A
	nsc add user -a A \
		--name test \
		--allow-pubsub 'test.>' \
		--allow-pubsub 'test' \
		--allow-pubsub '_INBOX.>' \
		--allow-pubsub '_R_' \
		--allow-pubsub '_R_.>' \
		--allow-sub latency.on.test

	# Add latency exporting for the test subject from account A.
	nsc add export -a A --latency latency.on.test --sampling 100 --service -s test

	# Add account B that imports services from A.
	nsc add account --name B
	nsc add user -a B \
		--name test \
		--allow-pubsub 'test.>' \
		--allow-pubsub 'test' \
		--allow-pubsub '_INBOX.>' \
		--allow-pubsub '_R_' \
		--allow-pubsub '_R_.>'

	nsc add import --account B \
		--src-account "$(nsc list accounts 2>&1 | awk '$2 == "A" {print $0}' | awk '{print $4}')" \
		--remote-subject test --service --local-subject test

	# Create account for STAN purposes.
	nsc add account --name STAN
	nsc add user --name stan

	# Generate accounts resolver config using the preload config
	(
		cd "$NATS_CONFIG_HOME"
		nsc generate config --mem-resolver --sys-account SYS >resolver.conf
	)

	if [[ "$SKIP_NSC_DIR_CHOWN" != "true" ]]; then
		chown -R 1000:1000 "$NSC_DIR"
	fi
}

main() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		-d | --dry-run)
			helm template \
				--set-file file.resolverConf=./nsc/config/resolver.conf \
				./nats
			shift
			;;
		--delete)
			helm uninstall nats-k8s
			shift
			;;
		-c)
			create_creds
			shift
			;;
		-i | --install)
			helm install \
				--set-file file.resolverConf=./nsc/config/resolver.conf \
				nats-k8s ./nats
			shift
			;;
		*)
			echo "invalid option: ${1}"
			exit 1
			;;
		esac
	done
}

main "$@"
