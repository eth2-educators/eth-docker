#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$(id -u)" = '0' ]; then
  chown -R prysmconsensus:prysmconsensus /var/lib/prysm
  exec gosu prysmconsensus docker-entrypoint.sh "$@"
fi

if [ -n "${JWT_SECRET}" ]; then
  echo -n "${JWT_SECRET}" > /var/lib/prysm/ee-secret/jwtsecret
  echo "JWT secret was supplied in .env"
fi

if [[ -O "/var/lib/prysm/ee-secret" ]]; then
  # In case someone specifies JWT_SECRET but it's not a distributed setup
  chmod 777 /var/lib/prysm/ee-secret
fi
if [[ -O "/var/lib/prysm/ee-secret/jwtsecret" ]]; then
  chmod 666 /var/lib/prysm/ee-secret/jwtsecret
fi

if [[ "${NETWORK}" =~ ^https?:// ]]; then
  echo "Custom testnet at ${NETWORK}"
  repo=$(awk -F'/tree/' '{print $1}' <<< "${NETWORK}")
  branch=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f1)
  config_dir=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f2-)
  echo "This appears to be the ${repo} repo, branch ${branch} and config directory ${config_dir}."
  # For want of something more amazing, let's just fail if git fails to pull this
  set -e
  if [ ! -d "/var/lib/prysm/testnet/${config_dir}" ]; then
    mkdir -p /var/lib/prysm/testnet
    cd /var/lib/prysm/testnet
    git init --initial-branch="${branch}"
    git remote add origin "${repo}"
    git config core.sparseCheckout true
    echo "${config_dir}" > .git/info/sparse-checkout
    git pull origin "${branch}"
  fi
  bootnodes="$(paste -s -d, "/var/lib/prysm/testnet/${config_dir}/bootstrap_nodes.txt")"
  deploy_block=$(cat "/var/lib/prysm/testnet/${config_dir}/deploy_block.txt")
  set +e
  __network="--chain-config-file=/var/lib/prysm/testnet/${config_dir}/config.yaml --genesis-state=/var/lib/prysm/testnet/${config_dir}/genesis.ssz \
--enable-debug-rpc-endpoints --bootstrap-node=${bootnodes} --contract-deployment-block=${deploy_block}"
else
  __network="--${NETWORK}"
fi

# Check whether we should rapid sync
if [ -n "${RAPID_SYNC_URL:+x}" ]; then
  __rapid_sync="--checkpoint-sync-url=${RAPID_SYNC_URL}"
  echo "Checkpoint sync enabled"
else
  __rapid_sync=""
fi

# Check whether we should use MEV Boost
if [ "${MEV_BOOST}" = "true" ]; then
  __mev_boost="--http-mev-relay=${MEV_NODE:-http://mev-boost:18550}"
  echo "MEV Boost enabled"
else
  __mev_boost=""
fi

if [ "${ARCHIVE_NODE}" = "true" ]; then
  echo "Prysm archive node without pruning"
  __prune="--slots-per-archive-point=32"
else
  __prune=""
fi

if [[ "${NETWORK}" = "sepolia" ]]; then
  GENESIS=/var/lib/prysm/genesis.ssz
  if [ ! -f "$GENESIS" ]; then
    echo "Fetching genesis file for Sepolia testnet"
    curl -fsSL -o "$GENESIS" https://github.com/eth-clients/sepolia/raw/main/metadata/genesis.ssz
  fi
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" "--genesis-state=$GENESIS" ${__network} ${__rapid_sync} ${__prune} ${__mev_boost} ${CL_EXTRAS}
elif [[ "${NETWORK}" = "holesky" ]]; then
  GENESIS=/var/lib/prysm/genesis.ssz
  if [ ! -f "$GENESIS" ]; then
    echo "Fetching genesis file for Holešky testnet"
    curl -fsSL -o "$GENESIS" https://github.com/eth-clients/holesky/raw/main/metadata/genesis.ssz
  fi
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" "--genesis-state=$GENESIS" ${__network} ${__rapid_sync} ${__prune} ${__mev_boost} ${CL_EXTRAS}
else
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__network} ${__rapid_sync} ${__prune} ${__mev_boost} ${CL_EXTRAS}
fi
