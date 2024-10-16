#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" = '0' ]; then
  chown -R geth:geth /var/lib/geth
  exec su-exec geth docker-entrypoint.sh "$@"
fi

if [ -n "${JWT_SECRET}" ]; then
  echo -n "${JWT_SECRET}" > /var/lib/geth/ee-secret/jwtsecret
  echo "JWT secret was supplied in .env"
fi

if [[ ! -f /var/lib/geth/ee-secret/jwtsecret ]]; then
  echo "Generating JWT secret"
  __secret1=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
  __secret2=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
  echo -n "${__secret1}""${__secret2}" > /var/lib/geth/ee-secret/jwtsecret
fi

if [[ -O "/var/lib/geth/ee-secret" ]]; then
  # In case someone specifies JWT_SECRET but it's not a distributed setup
  chmod 777 /var/lib/geth/ee-secret
fi
if [[ -O "/var/lib/geth/ee-secret/jwtsecret" ]]; then
  chmod 666 /var/lib/geth/ee-secret/jwtsecret
fi

__ancient=""

if [ -n "${ANCIENT_DIR}" ] && [ ! "${ANCIENT_DIR}" = ".nada" ]; then
  echo "Using separate ancient directory at ${ANCIENT_DIR}."
  __ancient="--datadir.ancient /var/lib/ancient"
fi

if [[ "${NETWORK}" =~ ^https?:// ]]; then
  echo "Custom testnet at ${NETWORK}"
  repo=$(awk -F'/tree/' '{print $1}' <<< "${NETWORK}")
  branch=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f1)
  config_dir=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f2-)
  echo "This appears to be the ${repo} repo, branch ${branch} and config directory ${config_dir}."
  # For want of something more amazing, let's just fail if git fails to pull this
  set -e
  if [ ! -d "/var/lib/geth/testnet/${config_dir}" ]; then
    mkdir -p /var/lib/geth/testnet
    cd /var/lib/geth/testnet
    git init --initial-branch="${branch}"
    git remote add origin "${repo}"
    git config core.sparseCheckout true
    echo "${config_dir}" > .git/info/sparse-checkout
    git pull origin "${branch}"
  fi
  bootnodes="$(paste -s -d, "/var/lib/geth/testnet/${config_dir}/bootnode.txt")"
  networkid="$(jq -r '.config.chainId' "/var/lib/geth/testnet/${config_dir}/genesis.json")"
  set +e
  __network="--bootnodes=${bootnodes} --networkid=${networkid} --http.api=eth,net,web3,debug,admin,txpool"
  if [ ! -d "/var/lib/geth/geth/chaindata/" ]; then
    geth init --datadir /var/lib/geth "/var/lib/geth/testnet/${config_dir}/genesis.json"
  fi
else
  __network="--${NETWORK}"
fi

# New or old datadir
if [ -d /var/lib/goethereum/geth/chaindata ]; then
  __datadir="--datadir /var/lib/goethereum"
else
  __datadir="--datadir /var/lib/geth"
fi

# Set verbosity
shopt -s nocasematch
case ${LOG_LEVEL} in
  error)
    __verbosity="--verbosity 1"
    ;;
  warn)
    __verbosity="--verbosity 2"
    ;;
  info)
    __verbosity="--verbosity 3"
    ;;
  debug)
    __verbosity="--verbosity 4"
    ;;
  trace)
    __verbosity="--verbosity 5"
    ;;
  *)
    echo "LOG_LEVEL ${LOG_LEVEL} not recognized"
    __verbosity=""
    ;;
esac

if [ "${ARCHIVE_NODE}" = "true" ]; then
  echo "Geth archive node without pruning"
  __prune="--syncmode=full --gcmode=archive"
else
  __prune=""
fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
exec "$@" ${__datadir} ${__ancient} ${__network} ${__prune} ${__verbosity} ${EL_EXTRAS}
