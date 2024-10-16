#!/bin/bash
set -Eeuo pipefail

if [ "$(id -u)" = '0' ]; then
  chown -R besu:besu /var/lib/besu
  exec gosu besu "${BASH_SOURCE[0]}" "$@"
fi

if [ -n "${JWT_SECRET}" ]; then
  echo -n "${JWT_SECRET}" > /var/lib/besu/ee-secret/jwtsecret
  echo "JWT secret was supplied in .env"
fi

if [[ ! -f /var/lib/besu/ee-secret/jwtsecret ]]; then
  echo "Generating JWT secret"
  __secret1=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
  __secret2=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
  echo -n "${__secret1}""${__secret2}" > /var/lib/besu/ee-secret/jwtsecret
fi

if [[ -O "/var/lib/besu/ee-secret" ]]; then
  # In case someone specifies JWT_SECRET but it's not a distributed setup
  chmod 777 /var/lib/besu/ee-secret
fi
if [[ -O "/var/lib/besu/ee-secret/jwtsecret" ]]; then
  chmod 666 /var/lib/besu/ee-secret/jwtsecret
fi

if [[ "${NETWORK}" =~ ^https?:// ]]; then
  echo "Custom testnet at ${NETWORK}"
  repo=$(awk -F'/tree/' '{print $1}' <<< "${NETWORK}")
  branch=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f1)
  config_dir=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f2-)
  echo "This appears to be the ${repo} repo, branch ${branch} and config directory ${config_dir}."
  # For want of something more amazing, let's just fail if git fails to pull this
  set -e
  if [ ! -d "/var/lib/besu/testnet/${config_dir}" ]; then
    mkdir -p /var/lib/besu/testnet
    cd /var/lib/besu/testnet
    git init --initial-branch="${branch}"
    git remote add origin "${repo}"
    git config core.sparseCheckout true
    echo "${config_dir}" > .git/info/sparse-checkout
    git pull origin "${branch}"
  fi
  bootnodes="$(paste -s -d, "/var/lib/besu/testnet/${config_dir}/bootnode.txt")"
  set +e
  __network="--genesis-file=/var/lib/besu/testnet/${config_dir}/besu.json --bootnodes=${bootnodes} \
--Xfilter-on-enr-fork-id=true --rpc-http-api=ADMIN,CLIQUE,MINER,ETH,NET,DEBUG,TXPOOL,ENGINE,TRACE,WEB3"
else
  __network="--network ${NETWORK}"
fi

if [ "${ARCHIVE_NODE}" = "true" ]; then
  echo "Besu archive node without pruning"
  __prune="--data-storage-format=FOREST --sync-mode=FULL"
else
  __prune=""
fi

__memtotal=$(awk '/MemTotal/ {printf "%d", int($2/1024/1024)}' /proc/meminfo)
if [ "${__memtotal}" -ge 60 ]; then
  __spec="--Xplugin-rocksdb-high-spec-enabled=true"
else
  __spec=""
fi

# New or old datadir
if [ -d /var/lib/besu-og/database ]; then
  __datadir="--data-path /var/lib/besu-og"
else
  __datadir="--data-path /var/lib/besu"
fi

# DiscV5 for IPV6
if [ "${IPV6:-false}" = "true" ]; then
  echo "Configuring Besu for discv5 for IPv6 advertisements"
  __ipv6="--Xv5-discovery-enabled"
else
  __ipv6=""
fi

if [ -f /var/lib/besu/prune-marker ]; then
  rm -f /var/lib/besu/prune-marker
  if [ "${ARCHIVE_NODE}" = "true" ]; then
    echo "Besu is an archive node. Not attempting to prune trie-logs: Aborting."
    exit 1
  fi
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__datadir} ${__network} ${__prune} ${EL_EXTRAS} storage trie-log prune
else
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__datadir} ${__network} ${__ipv6} ${__prune} ${__spec} ${EL_EXTRAS}
fi
