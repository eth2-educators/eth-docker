#!/usr/bin/env bash

if [ "$(id -u)" = '0' ]; then
  chown -R user:user /var/lib/nimbus
  exec su-exec user docker-entrypoint-vc.sh "$@"
fi

# Remove old low-entropy token, related to Sigma Prime security audit
# This detection isn't perfect - a user could recreate the token without ./ethd update
if [[ -f /var/lib/nimbus/api-token.txt && "$(date +%s -r /var/lib/nimbus/api-token.txt)" -lt "$(date +%s --date="2023-05-02 09:00:00")" ]]; then
    rm /var/lib/nimbus/api-token.txt
fi

if [ ! -f /var/lib/nimbus/api-token.txt ]; then
    __token=api-token-0x$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)$(head -c 8 /dev/urandom | od -A n -t u8 | tr -d '[:space:]' | sha256sum | head -c 32)
    echo "$__token" > /var/lib/nimbus/api-token.txt
fi

# Check whether we should enable doppelganger protection
if [ "${DOPPELGANGER}" = "true" ]; then
  __doppel="--doppelganger-detection=true"
  echo "Doppelganger protection enabled, VC will pause for 2 epochs"
else
  __doppel="--doppelganger-detection=false"
fi

# Check whether we should use MEV Boost
if [ "${MEV_BOOST}" = "true" ]; then
  __mev_boost="--payload-builder=true"
  echo "MEV Boost enabled"
else
  __mev_boost=""
fi

__log_level="--log-level=${LOG_LEVEL^^}"

# Web3signer URL
if [ "${WEB3SIGNER}" = "true" ]; then
  __w3s_url="--web3-signer-url=http://web3signer:9000"
  while true; do
    if curl -s -m 5 http://web3signer:9000 &> /dev/null; then
        echo "Web3signer is up, starting Nimbus"
        break
    else
        echo "Waiting for Web3signer to be reachable..."
        sleep 5
    fi
  done
else
  __w3s_url=""
fi

# Distributed attestation aggregation
if [ "${ENABLE_DIST_ATTESTATION_AGGR}" =  "true" ]; then
  __att_aggr="--distributed"
else
  __att_aggr=""
fi

if [ "${DEFAULT_GRAFFITI}" = "true" ]; then
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__w3s_url} ${__log_level} ${__doppel} ${__mev_boost} ${__att_aggr} ${VC_EXTRAS}
else
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__w3s_url} "--graffiti=${GRAFFITI}" ${__log_level} ${__doppel} ${__mev_boost} ${__att_aggr} ${VC_EXTRAS}
fi
