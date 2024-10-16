#!/usr/bin/env bash

if [ "$(id -u)" = '0' ]; then
  chown -R teku:teku /var/lib/teku
  exec gosu teku docker-entrypoint.sh "$@"
fi

if [ -f /var/lib/teku/teku-keyapi.keystore ]; then
    if [ "$(date +%s -r /var/lib/teku/teku-keyapi.keystore)" -lt "$(date +%s --date="300 days ago")" ]; then
       rm /var/lib/teku/teku-keyapi.keystore
    elif ! openssl x509 -noout -ext subjectAltName -in /var/lib/teku/teku-keyapi.crt | grep -q 'DNS:consensus'; then
       rm /var/lib/teku/teku-keyapi.keystore
    fi
fi

if [ ! -f /var/lib/teku/teku-keyapi.keystore ]; then
    __password=$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum| head -c 32)
    echo "$__password" > /var/lib/teku/teku-keyapi.password
    openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes -keyout /var/lib/teku/teku-keyapi.key -out /var/lib/teku/teku-keyapi.crt -subj '/CN=teku-keyapi-cert' -extensions san -config <( \
      echo '[req]'; \
      echo 'distinguished_name=req'; \
      echo '[san]'; \
      echo 'subjectAltName=DNS:localhost,DNS:consensus,DNS:validator,DNS:vc,IP:127.0.0.1')
    openssl pkcs12 -export -in /var/lib/teku/teku-keyapi.crt -inkey /var/lib/teku/teku-keyapi.key -out /var/lib/teku/teku-keyapi.keystore -name teku-keyapi -passout pass:"$__password"
fi

if [ -n "${JWT_SECRET}" ]; then
  echo -n "${JWT_SECRET}" > /var/lib/teku/ee-secret/jwtsecret
  echo "JWT secret was supplied in .env"
fi

if [[ -O "/var/lib/teku/ee-secret" ]]; then
  # In case someone specifies JWT_SECRET but it's not a distributed setup
  chmod 777 /var/lib/teku/ee-secret
fi
if [[ -O "/var/lib/teku/ee-secret/jwtsecret" ]]; then
  chmod 666 /var/lib/teku/ee-secret/jwtsecret
fi

# Check whether we should rapid sync
if [ -n "${RAPID_SYNC_URL:+x}" ]; then
    if [ "${ARCHIVE_NODE}" = "true" ]; then
        echo "Teku archive node cannot use checkpoint sync: Syncing from genesis."
        __rapid_sync="--ignore-weak-subjectivity-period-enabled=true"
      if [ "${NETWORK}" = "holesky" ]; then
        __rapid_sync+=" --initial-state=https://checkpoint-sync.holesky.ethpandaops.io/eth/v2/debug/beacon/states/genesis"
      fi
    else
        __rapid_sync="--checkpoint-sync-url=${RAPID_SYNC_URL}"
        echo "Checkpoint sync enabled"
    fi
else
    __rapid_sync="--ignore-weak-subjectivity-period-enabled=true"
    if [ "${NETWORK}" = "holesky" ]; then
      __rapid_sync+=" --initial-state=https://checkpoint-sync.holesky.ethpandaops.io/eth/v2/debug/beacon/states/genesis"
    fi
fi

if [[ "${NETWORK}" =~ ^https?:// ]]; then
  echo "Custom testnet at ${NETWORK}"
  repo=$(awk -F'/tree/' '{print $1}' <<< "${NETWORK}")
  branch=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f1)
  config_dir=$(awk -F'/tree/' '{print $2}' <<< "${NETWORK}" | cut -d'/' -f2-)
  echo "This appears to be the ${repo} repo, branch ${branch} and config directory ${config_dir}."
  # For want of something more amazing, let's just fail if git fails to pull this
  set -e
  if [ ! -d "/var/lib/teku/testnet/${config_dir}" ]; then
    mkdir -p /var/lib/teku/testnet
    cd /var/lib/teku/testnet
    git init --initial-branch="${branch}"
    git remote add origin "${repo}"
    git config core.sparseCheckout true
    echo "${config_dir}" > .git/info/sparse-checkout
    git pull origin "${branch}"
  fi
  bootnodes="$(paste -s -d, "/var/lib/teku/testnet/${config_dir}/bootstrap_nodes.txt")"
  set +e
  __rapid_sync="--initial-state=/var/lib/teku/testnet/${config_dir}/genesis.ssz --ignore-weak-subjectivity-period-enabled=true"
  __network="--network=/var/lib/teku/testnet/${config_dir}/config.yaml --p2p-discovery-bootnodes=${bootnodes} \
--data-storage-non-canonical-blocks-enabled=true --Xlog-include-p2p-warnings-enabled \
--metrics-block-timing-tracking-enabled --Xmetrics-blob-sidecars-storage-enabled=true \
--Xpeer-rate-limit=100000 --Xpeer-request-limit=1000"
else
  __network="--network=${NETWORK}"
fi

# Check whether we should use MEV Boost
if [ "${MEV_BOOST}" = "true" ]; then
  __mev_boost="--validators-builder-registration-default-enabled --validators-proposer-blinded-blocks-enabled --builder-endpoint=${MEV_NODE:-http://mev-boost:18550}"
  echo "MEV Boost enabled"
else
  __mev_boost=""
fi

# Check whether we should send stats to beaconcha.in
if [ -n "${BEACON_STATS_API}" ]; then
  __beacon_stats="--metrics-publish-endpoint=https://beaconcha.in/api/v1/client/metrics?apikey=${BEACON_STATS_API}&machine=${BEACON_STATS_MACHINE}"
  echo "Beacon stats API enabled"
else
  __beacon_stats=""
fi

# Check whether we should enable doppelganger protection
if [ "${DOPPELGANGER}" = "true" ]; then
  __doppel="--doppelganger-detection-enabled=true"
  echo "Doppelganger protection enabled, VC will pause for 2 epochs"
else
  __doppel=""
fi

if [ "${ARCHIVE_NODE}" = "true" ]; then
  echo "Teku archive node without pruning"
  __prune="--data-storage-mode=ARCHIVE"
else
  __prune="--data-storage-mode=MINIMAL"
fi

# Web3signer URL
if [[ "${EMBEDDED_VC}" = "true" && "${WEB3SIGNER}" = "true" ]]; then
  __w3s_url="--validators-external-signer-url http://web3signer:9000"
#  while true; do
#    if curl -s -m 5 http://web3signer:9000 &> /dev/null; then
#        echo "web3signer is up, starting Teku"
#        break
#    else
#        echo "Waiting for web3signer to be reachable..."
#        sleep 5
#    fi
#  done
else
  __w3s_url=""
fi

if [ "${IPV6}" = "true" ]; then
  echo "Configuring Teku to listen on IPv6 ports"
  __ipv6="--p2p-interface 0.0.0.0,:: --p2p-port-ipv6 ${CL_IPV6_P2P_PORT:-9090}"
# ENR discovery on v6 is not yet working, likely too few peers. Manual for now
  __ipv4_pattern="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
  __ipv6_pattern="^[0-9A-Fa-f]{1,4}:" # Sufficient to check the start
  set +e
  __public_v4=$(curl -s -4 ifconfig.me)
  __public_v6=$(curl -s -6 ifconfig.me)
  set -e
  __valid_v4=0
  if [[ "$__public_v4" =~ $__ipv4_pattern ]]; then
    __valid_v4=1
  fi
  if [[ "$__public_v6" =~ $__ipv6_pattern ]]; then
    if [ "${__valid_v4}" -eq 1 ]; then
      __ipv6+=" --p2p-advertised-ips ${__public_v4},${__public_v6}"
    else
      __ipv6+=" --p2p-advertised-ip ${__public_v6}"
    fi
  fi
else
  __ipv6=""
fi

if [ "${DEFAULT_GRAFFITI}" = "true" ]; then
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__network} ${__w3s_url} ${__mev_boost} ${__rapid_sync} ${__prune} ${__beacon_stats} ${__doppel} ${__ipv6} ${CL_EXTRAS} ${VC_EXTRAS}
else
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__network} "--validators-graffiti=${GRAFFITI}" ${__w3s_url} ${__mev_boost} ${__rapid_sync} ${__prune} ${__beacon_stats} ${__doppel} ${__ipv6} ${CL_EXTRAS} ${VC_EXTRAS}
fi
