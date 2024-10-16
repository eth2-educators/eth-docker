#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$(id -u)" = '0' ]; then
  chown -R erigon:erigon /var/lib/erigon
  exec su-exec erigon "${BASH_SOURCE[0]}" "$@"
fi

if [ -n "${JWT_SECRET}" ]; then
  echo -n "${JWT_SECRET}" > /var/lib/erigon/ee-secret/jwtsecret
  echo "JWT secret was supplied in .env"
fi

if [[ ! -f /var/lib/erigon/ee-secret/jwtsecret ]]; then
  echo "Generating JWT secret"
  __secret1=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
  __secret2=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
  echo -n "${__secret1}""${__secret2}" > /var/lib/erigon/ee-secret/jwtsecret
fi

if [[ -O "/var/lib/erigon/ee-secret" ]]; then
  # In case someone specifies JWT_SECRET but it's not a distributed setup
  chmod 777 /var/lib/erigon/ee-secret
fi
if [[ -O "/var/lib/erigon/ee-secret/jwtsecret" ]]; then
  chmod 666 /var/lib/erigon/ee-secret/jwtsecret
fi

if [[ "${NETWORK}" =~ ^https?:// ]]; then
  echo "Custom testnet at ${NETWORK}"
  repo=$(awk -F'/tree/' '{print $1}' <<< "${NETWORK}")
  branch=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f1)
  config_dir=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f2-)
  echo "This appears to be the ${repo} repo, branch ${branch} and config directory ${config_dir}."
  # For want of something more amazing, let's just fail if git fails to pull this
  set -e
  if [ ! -d "/var/lib/erigon/testnet/${config_dir}" ]; then
    mkdir -p /var/lib/erigon/testnet
    cd /var/lib/erigon/testnet
    git init --initial-branch="${branch}"
    git remote add origin "${repo}"
    git config core.sparseCheckout true
    echo "${config_dir}" > .git/info/sparse-checkout
    git pull origin "${branch}"
  fi
  bootnodes="$(paste -s -d, "/var/lib/erigon/testnet/${config_dir}/bootnode.txt")"
  networkid="$(jq -r '.config.chainId' "/var/lib/erigon/testnet/${config_dir}/genesis.json")"
  set +e
  __network="--bootnodes=${bootnodes} --networkid=${networkid} --http.api=eth,erigon,engine,web3,net,debug,trace,txpool,admin"
  if [ ! -d /var/lib/erigon/chaindata ]; then
    erigon init --datadir /var/lib/erigon "/var/lib/erigon/testnet/${config_dir}/genesis.json"
  fi
else
  __network="--chain ${NETWORK} --http.api web3,eth,net,engine"
fi

__caplin=""
__db_params=""
# Literal match intended
# shellcheck disable=SC2076
if [[ "${DOCKER_TAG}" =~ "2." || "${DOCKER_TAG}" = "latest" ]]; then
# Check for network, and set prune accordingly
  if [ "${ARCHIVE_NODE}" = "true" ]; then
    echo "Erigon archive node without pruning"
    __prune=""
  else
    if [[ "${NETWORK}" = "mainnet" ]]; then
      echo "mainnet: Running with prune.r.before=11052984 for eth deposit contract"
      __prune="--prune=htc --prune.r.before=11052984"
    elif [[ "${NETWORK}" = "goerli" ]]; then
      echo "goerli: Running with prune.r.before=4367322 for eth deposit contract"
      __prune="--prune=htc --prune.r.before=4367322"
    elif [[ "${NETWORK}" = "sepolia" ]]; then
      echo "sepolia: Running with prune.r.before=1273020 for eth deposit contract"
      __prune="--prune=htc --prune.r.before=1273020"
    elif [[ "${NETWORK}" = "gnosis" ]]; then
      echo "gnosis: Running with prune.r.before=19469077 for gno deposit contract"
      __prune="--prune=htc --prune.r.before=19469077"
    elif [[ "${NETWORK}" = "holesky" ]]; then
      echo "holesky: Running without prune.r for eth deposit contract"
      __prune="--prune=htc"
    elif [[ "${NETWORK}" =~ ^https?:// ]]; then
      echo "Custom testnet: Running without prune.r for eth deposit contract"
      __prune="--prune=htc"
    else
      echo "Unable to determine eth deposit contract, running without prune.r"
      __prune="--prune=htc"
    fi
  fi
  __db_params="--db.pagesize 16K --db.size.limit 8TB"
else  # Erigon v3
  if [ "${ARCHIVE_NODE}" = "true" ]; then
    echo "Erigon archive node without pruning"
    __prune="--prune.mode=archive"
  else
    echo "Erigon full node with pruning"
    __prune="--prune.mode=full"
  fi
  if [[ "${COMPOSE_FILE}" =~ (prysm\.yml|prysm-cl-only\.yml|lighthouse\.yml|lighthouse-cl-only\.yml|lodestar\.yml| \
      lodestar-cl-only\.yml|nimbus\.yml|nimbus-cl-only\.yml|nimbus-allin1\.yml|teku\.yml|teku-cl-only\.yml| \
      teku-allin1\.yml|grandine\.yml|grandine-cl-only\.yml|grandine-allin1\.yml) ]]; then
    __caplin="--externalcl=true"
  else
    echo "Running Erigon with internal Caplin consensus layer client"
    __caplin="--caplin.discovery.addr=0.0.0.0 --caplin.discovery.port=${CL_P2P_PORT} --caplin.backfilling.blob=true"
    __caplin+=" --caplin.discovery.tcpport=${CL_P2P_PORT} --caplin.backfilling=true --caplin.validator-monitor=true"
    __caplin+=" --beacon.api=beacon,builder,config,debug,events,node,validator,lighthouse"
    __caplin+=" --beacon.api.addr=0.0.0.0 --beacon.api.port=${CL_REST_PORT} --beacon.api.cors.allow-origins=*"
    if [ "${MEV_BOOST}" = "true" ]; then
      __caplin+=" --caplin.mev-relay-url=${MEV_NODE}"
      echo "MEV Boost enabled"
    fi
    if [ "${ARCHIVE_NODE}" = "true" ]; then
      __caplin+=" --caplin.archive=true"
    fi
    if [ -n "${RAPID_SYNC_URL}" ]; then
      __caplin+=" --caplin.checkpoint-sync-url=${RAPID_SYNC_URL}"
      echo "Checkpoint sync enabled"
    else
      __caplin+=" --caplin.checkpoint-sync.disable=true"
    fi
    echo "Caplin parameters: ${__caplin}"
  fi
fi

if [ "${IPV6}" = "true" ]; then
  echo "Configuring Erigon for discv5 for IPv6 advertisements"
  __ipv6="--v5disc"
else
  __ipv6=""
fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${__ipv6} ${__network} ${__prune} ${__db_params} ${__caplin} ${EL_EXTRAS}
