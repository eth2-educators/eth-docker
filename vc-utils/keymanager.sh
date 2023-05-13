#!/usr/bin/env bash

call_api() {
    set +e
    if [ -z "${__api_data}" ]; then
        if [ "${__api_tls}" = "true" ]; then
            __code=$(curl -k -m 60 -s --show-error -o /tmp/result.txt -w "%{http_code}" -X "${__http_method}" -H "Accept: application/json" -H "Authorization: Bearer $__token" \
                https://"${__api_container}":"${__api_port}"/"${__api_path}")
        else
            __code=$(curl -m 60 -s --show-error -o /tmp/result.txt -w "%{http_code}" -X "${__http_method}" -H "Accept: application/json" -H "Authorization: Bearer $__token" \
                http://"${__api_container}":"${__api_port}"/"${__api_path}")
        fi
    else
        if [ "${__api_tls}" = "true" ]; then
            __code=$(curl -k -m 60 -s --show-error -o /tmp/result.txt -w "%{http_code}" -X "${__http_method}" -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $__token" \
                --data "${__api_data}" https://"${__api_container}":"${__api_port:-7500}"/"${__api_path}")
        else
            __code=$(curl -m 60 -s --show-error -o /tmp/result.txt -w "%{http_code}" -X "${__http_method}" -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $__token" \
                --data "${__api_data}" http://"${__api_container}":"${__api_port:-7500}"/"${__api_path}")
        fi
    fi
    __return=$?
    if [ $__return -ne 0 ]; then
        echo "Error encountered while trying to call the keymanager API via curl."
        echo "Please make sure ${__api_container} is up and shows the key manager API, port ${__api_port}, enabled."
        echo "Error code $__return"
        exit $__return
    fi
    if [ -f /tmp/result.txt ]; then
        __result=$(cat /tmp/result.txt)
    else
        echo "Error encountered while trying to call the keymanager API via curl."
        echo "HTTP code: ${__code}"
        exit 1
    fi
}

get-token() {
set +e
    if [ -z "${PRYSM:+x}" ]; then
        __token=$(< "${__token_file}")
    else
        __token=$(sed -n 2p "${__token_file}")
    fi
    __return=$?
    if [ $__return -ne 0 ]; then
        echo "Error encountered while trying to get the keymanager API token."
        echo "Please make sure ${__api_container} is up and shows the key manager API, port ${__api_port}, enabled."
        exit $__return
    fi
set -e
}

print-api-token() {
    get-token
    echo "${__token}"
}

get-prysm-wallet() {
    if [ -f /var/lib/prysm/password.txt ]; then
        echo "The password for the Prysm wallet is:"
        cat /var/lib/prysm/password.txt
    else
        echo "No stored password found for a Prysm wallet."
    fi
}

recipient-get() {
    if [ -z "$__pubkey" ]; then
      echo "Please specify a validator public key"
      exit 0
    fi
    get-token
    __api_path=eth/v1/validator/$__pubkey/feerecipient
    __api_data=""
    __http_method=GET
    call_api
    case $__code in
        200) echo "The fee recipient for the validator with public key $__pubkey is:"; echo "$__result" | jq -r '.data.ethaddress'; exit 0;;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        404) echo "Path not found error. Was that the right pubkey? Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

recipient-set() {
    if [ -z "$__pubkey" ]; then
      echo "Please specify a validator public key"
      exit 0
    fi
    if [ -z "$__address" ]; then
      echo "Please specify a fee recipient address"
      exit 0
    fi
    get-token
    __api_path=eth/v1/validator/$__pubkey/feerecipient
    __api_data="{\"ethaddress\": \"$__address\" }"
    __http_method=POST
    call_api
    case $__code in
        202) echo "The fee recipient for the validator with public key $__pubkey was updated."; exit 0;;
        400) echo "The pubkey or address was formatted wrong. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        404) echo "Path not found error. Was that the right pubkey? Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

recipient-delete() {
    if [ -z "$__pubkey" ]; then
      echo "Please specify a validator public key"
      exit 0
    fi
    get-token
    __api_path=eth/v1/validator/$__pubkey/feerecipient
    __api_data=""
    __http_method=DELETE
    call_api
    case $__code in
        204) echo "The fee recipient for the validator with public key $__pubkey was set back to default."; exit 0;;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "A fee recipient was found, but cannot be deleted. It may be in a configuration file. Message: $(echo "$__result" | jq -r '.message')"; exit 0;;
        404) echo "The key was not found on the server, nothing to delete. Message: $(echo "$__result" | jq -r '.message')"; exit 0;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

gas-get() {
    if [ -z "$__pubkey" ]; then
      echo "Please specify a validator public key"
      exit 0
    fi
    get-token
    __api_path=eth/v1/validator/$__pubkey/gas_limit
    __api_data=""
    __http_method=GET
    call_api
    case $__code in
        200) echo "The execution gas limit for the validator with public key $__pubkey is:"; echo "$__result" | jq -r '.data.gas_limit'; exit 0;;
        400) echo "The pubkey was formatted wrong. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        404) echo "Path not found error. Was that the right pubkey? Error: $(echo "$__result" | jq -r '.message')"; exit 0;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

gas-set() {
    if [ -z "$__pubkey" ]; then
      echo "Please specify a validator public key"
      exit 0
    fi
    if [ -z "$__limit" ]; then
      echo "Please specify a gas limit"
      exit 0
    fi
    get-token
    __api_path=eth/v1/validator/$__pubkey/gas_limit
    __api_data="{\"gas_limit\": \"$__limit\" }"
    __http_method=POST
    call_api
    case $__code in
        202) echo "The gas limit for the validator with public key $__pubkey was updated."; exit 0;;
        400) echo "The pubkey or limit was formatted wrong. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        404) echo "Path not found error. Was that the right pubkey? Error: $(echo "$__result" | jq -r '.message')"; exit 0;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

gas-delete() {
    if [ -z "$__pubkey" ]; then
      echo "Please specify a validator public key"
      exit 0
    fi
    get-token
    __api_path=eth/v1/validator/$__pubkey/gas_limit
    __api_data=""
    __http_method=DELETE
    call_api
    case $__code in
        204) echo "The gas limit for the validator with public key $__pubkey was set back to default."; exit 0;;
        400) echo "The pubkey was formatted wrong. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "A gas limit was found, but cannot be deleted. It may be in a configuration file. Message: $(echo "$__result" | jq -r '.message')"; exit 0;;
        404) echo "The key was not found on the server, nothing to delete. Message: $(echo "$__result" | jq -r '.message')"; exit 0;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

__validator-list-call() {
    __api_data=""
    __http_method=GET
    call_api
    case $__code in
        200);;
        401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
        *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
    esac
}

validator-list() {
    __api_path=eth/v1/keystores
    if [ "${WEB3SIGNER}" = "true" ]; then
        __token=NIL
        __vc_api_container=${__api_container}
        __api_container=web3signer
        __vc_api_port=${__api_port}
        __api_port=9000
        __vc_api_tls=${__api_tls}
        __api_tls=false
    else
        get-token
    fi
    __validator-list-call
    if [ "$(echo "$__result" | jq '.data | length')" -eq 0 ]; then
        echo "No keys loaded"
    else
        echo "Validator public keys"
        echo "$__result" | jq -r '.data[].validating_pubkey'
    fi
    if [ "${WEB3SIGNER}" = "true" ]; then
        get-token
        __api_path=eth/v1/remotekeys
        __api_container=${__vc_api_container}
        __api_port=${__vc_api_port}
        __api_tls=${__vc_api_tls}
        __validator-list-call
        if [ "$(echo "$__result" | jq '.data | length')" -eq 0 ]; then
            echo "No keys registered"
        else
            echo "Keys registered"
            echo "$__result" | jq -rc '.data[] | [.pubkey, .url] | join(" ")'
        fi
    fi
}

validator-delete() {
    if [ -z "${__pubkey}" ]; then
      echo "Please specify a validator public key to delete, or \"all\""
      exit 0
    fi
    __pubkeys=()
    __api_path=eth/v1/keystores
    if [ "${__pubkey}" = "all" ]; then
        if [ "${WEB3SIGNER}" = "true" ]; then
            echo "WARNING - this will delete all currently loaded keys from web3signer and the validator client."
        else
            echo "WARNING - this will delete all currently loaded keys from the validator client."
        fi
        echo
        read -rp "Do you wish to continue with key deletion? (No/yes) " yn
        case $yn in
            [Yy][Ee][Ss]) ;;
            * ) echo "Aborting key deletion"; exit 0;;
        esac
        if [ "${WEB3SIGNER}" = "true" ]; then
            __token=NIL
            __vc_api_container=${__api_container}
            __api_container=web3signer
            __vc_api_port=${__api_port}
            __api_port=9000
            __vc_api_tls=${__api_tls}
            __api_tls=false
        else
            get-token
        fi

        __validator-list-call
        if [ "$(echo "$__result" | jq '.data | length')" -eq 0 ]; then
            echo "No keys loaded, cannot delete anything"
            return
        else
            __keys_to_array=$(echo "$__result" | jq -r '.data[].validating_pubkey' | tr '\n' ' ')
# Word splitting is desired for the array
# shellcheck disable=SC2206
            __pubkeys+=( ${__keys_to_array} )
            if [ "${WEB3SIGNER}" = "true" ]; then
                __api_container=${__vc_api_container}
                __api_port=${__vc_api_port}
                __api_tls=${__vc_api_tls}
            fi
        fi
    else
        __pubkeys+=( "${__pubkey}" )
    fi

    for __pubkey in "${__pubkeys[@]}"; do
        if [ "${WEB3SIGNER}" = "true" ]; then
            __token=NIL
            __vc_api_container=${__api_container}
            __api_container=web3signer
            __vc_api_port=${__api_port}
            __api_port=9000
            __vc_api_tls=${__api_tls}
            __api_tls=false
        else
            get-token
        fi

        __api_path=eth/v1/keystores
        __api_data="{\"pubkeys\":[\"$__pubkey\"]}"
        __http_method=DELETE
        call_api
        case $__code in
            200) ;;
            400) echo "The pubkey was formatted wrong. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
        esac

        __status=$(echo "$__result" | jq -r '.data[].status')
        case ${__status,,} in
            error)
                echo "Validator ${__pubkey} was found but an error was encountered trying to delete it:"
                echo "$__result" | jq -r '.data[].message'
                ;;
            not_active)
                __file=validator_keys/slashing_protection-${__pubkey::10}--${__pubkey:90}.json
                echo "Validator ${__pubkey} is not actively loaded."
                echo "$__result" | jq '.slashing_protection | fromjson' > /"$__file"
                chmod 644 /"$__file"
                echo "Slashing protection data written to .eth/$__file"
                ;;
            deleted)
                __file=validator_keys/slashing_protection-${__pubkey::10}--${__pubkey:90}.json
                echo "Validator ${__pubkey} deleted."
                echo "$__result" | jq '.slashing_protection | fromjson' > /"$__file"
                chmod 644 /"$__file"
                echo "Slashing protection data written to .eth/$__file"
                ;;
            not_found)
                echo "The validator ${__pubkey} was not found in the keystore, no slashing protection data returned."
                ;;
            * )
                echo "Unexpected status $__status. This may be a bug"
                exit 1
                ;;
        esac
        # Remove remote registration
        if [ "${WEB3SIGNER}" = "true" ]; then
            __api_container=${__vc_api_container}
            __api_port=${__vc_api_port}
            __api_tls=${__vc_api_tls}

            get-token
            __api_path=eth/v1/remotekeys
            __api_data="{\"pubkeys\":[\"$__pubkey\"]}"
            __http_method=DELETE
            call_api
            case $__code in
                200) ;;
                401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
                403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
                500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
                *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
            esac

            __status=$(echo "$__result" | jq -r '.data[].status')
            case ${__status,,} in
                error)
                    echo "Remote registration for validator ${__pubkey} was found but an error was encountered trying to delete it:"
                    echo "$__result" | jq -r '.data[].message'
                    ;;
                not_active)
                    echo "Validator ${__pubkey} is not actively loaded."
                    ;;
                deleted)
                    echo "Remote registration for validator ${__pubkey} deleted."
                    ;;
                not_found)
                    echo "The validator ${__pubkey} was not found in the registration list."
                    ;;
                *)
                    echo "Unexpected status $__status. This may be a bug"
                    exit 1
                    ;;
            esac
        fi
    done
}

validator-import() {
    __num_files=$(find /validator_keys -maxdepth 1 -type f -name 'keystore*.json' | wc -l)
    if [ "$__num_files" -eq 0 ]; then
        echo "No keystore*.json files found in .eth/validator_keys/"
        echo "Nothing to do"
        exit 0
    fi

    __non_interactive=0
    if echo "$@" | grep -q '.*--non-interactive.*' 2>/dev/null ; then
      __non_interactive=1
    fi

    if [ ${__non_interactive} = 1 ]; then
        __password="${KEYSTORE_PASSWORD}"
        __justone=1
    else
        echo "WARNING - imported keys are immediately live. If these keys exist elsewhere,"
        echo "you WILL get slashed. If it has been less than 15 minutes since you deleted them elsewhere,"
        echo "you are at risk of getting slashed. Exercise caution"
        echo
        while true; do
            read -rp "I understand these dire warnings and wish to proceed with key import (No/yes) " yn
            case $yn in
                [Yy][Ee][Ss]) break;;
                [Nn]* ) echo "Aborting import"; exit 0;;
                * ) echo "Please answer yes or no.";;
            esac
        done
        if [ "$__num_files" -gt 1 ]; then
            while true; do
                read -rp "Do all validator keys have the same password? (y/n) " yn
                case $yn in
                    [Yy]* ) __justone=1; break;;
                    [Nn]* ) __justone=0; break;;
                    * ) echo "Please answer yes or no.";;
                esac
            done
        else
            __justone=1
        fi
        if [ $__justone -eq 1 ]; then
            while true; do
                read -srp "Please enter the password for your validator key(s): " __password
                echo
                read -srp "Please re-enter the password: " __password2
                echo
                if [ "$__password" == "$__password2" ]; then
                    break
                else
                    echo "The two entered passwords do not match, please try again."
                    echo
                fi
            done
            echo
        fi
    fi
    __imported=0
    __skipped=0
    __errored=0
    __registered=0
    __reg_skipped=0
    __reg_errored=0
    for __keyfile in /validator_keys/keystore*.json; do
        [ -f "$__keyfile" ] || continue
        __pubkey=0x$(jq -r '.pubkey' < "$__keyfile")
        if [ $__justone -eq 0 ]; then
            while true; do
                read -srp "Please enter the password for your validator key stored in $__keyfile with public key $__pubkey: " __password
                echo
                read -srp "Please re-enter the password: " __password2
                echo
                if [ "$__password" == "$__password2" ]; then
                    break
                else
                    echo "The two entered passwords do not match, please try again."
                    echo
                fi
                echo
            done
        fi
        __do_a_protec=0
        __found_one=0
        for __protectfile in /validator_keys/slashing_protection*.json; do
            [ -f "$__protectfile" ] || continue
            if grep -q "$__pubkey" "$__protectfile"; then
                __found_one=1
                echo "Found slashing protection import file $__protectfile for $__pubkey"
                if [ "$(jq ".data[] | select(.pubkey==\"$__pubkey\") | .signed_blocks | length" < "$__protectfile")" -gt 0 ] \
                    || [ "$(jq ".data[] | select(.pubkey==\"$__pubkey\") | .signed_attestations | length" < "$__protectfile")" -gt 0 ]; then
                    __do_a_protec=1
                    echo "It will be imported"
                else
                    echo "WARNING: The file does not contain importable data and will be skipped."
                    echo "Your validator will be imported WITHOUT slashing protection data."
                fi
                break
            fi
        done
        if [ "${__found_one}" -eq 0 ]; then
                echo "No viable slashing protection import file found for $__pubkey."
                echo "This is expected if this is a new key."
                echo "Proceeding without slashing protection import."
        fi
        __keystore_json=$(< "$__keyfile")
        if [ "$__do_a_protec" -eq 1 ]; then
            __protect_json=$(jq "select(.data[].pubkey==\"$__pubkey\") | tojson" < "$__protectfile")
        else
            __protect_json=""
        fi
        echo "$__protect_json" > /tmp/protect.json
        if [ "$__do_a_protec" -eq 0 ]; then
            jq --arg keystore_value "$__keystore_json" --arg password_value "$__password" '. | .keystores += [$keystore_value] | .passwords += [$password_value]' <<< '{}' >/tmp/apidata.txt
        else
            jq --arg keystore_value "$__keystore_json" --arg password_value "$__password" --slurpfile protect_value /tmp/protect.json '. | .keystores += [$keystore_value] | .passwords += [$password_value] | . += {slashing_protection: $protect_value[0]}' <<< '{}' >/tmp/apidata.txt
        fi

        if [ "${WEB3SIGNER}" = "true" ]; then
            __token=NIL
            __vc_api_container=${__api_container}
            __api_container=web3signer
            __vc_api_port=${__api_port}
            __api_port=9000
            __vc_api_tls=${__api_tls}
            __api_tls=false
        else
            get-token
        fi

        __api_data=@/tmp/apidata.txt
        __api_path=eth/v1/keystores
        __http_method=POST
        call_api
        case $__code in
            200) ;;
            400) echo "The pubkey was formatted wrong. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
        esac
        if ! echo "$__result" | grep -q "data"; then
           echo "The key manager API query failed. Output:"
           echo "$__result"
           exit 1
        fi
        __status=$(echo "$__result" | jq -r '.data[].status')
        case ${__status,,} in
            error)
                echo "An error was encountered trying to import the key $__pubkey:"
                echo "$__result" | jq -r '.data[].message'
                echo
                (( __errored+=1 ))
                continue
                ;;
            imported)
                echo "Validator key was successfully imported: $__pubkey"
                (( __imported+=1 ))
                ;;
            duplicate)
                echo "Validator key is a duplicate and was skipped: $__pubkey"
                (( __skipped+=1 ))
                ;;
            *)
                echo "Unexpected status $__status. This may be a bug"
                exit 1
                ;;
        esac
        # Add remote registration
        if [ "${WEB3SIGNER}" = "true" ]; then
            __api_container=${__vc_api_container}
            __api_port=${__vc_api_port}
            __api_tls=${__vc_api_tls}

            jq --arg pubkey_value "$__pubkey" --arg url_value "http://web3signer:9000" '. | .remote_keys += [{"pubkey": $pubkey_value, "url": $url_value}]' <<< '{}' >/tmp/apidata.txt

            get-token
            __api_data=@/tmp/apidata.txt
            __api_path=eth/v1/remotekeys
            __http_method=POST
            call_api
            case $__code in
                200) ;;
                401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
                403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
                500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
                *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
            esac
            if ! echo "$__result" | grep -q "data"; then
               echo "The key manager API query failed. Output:"
               echo "$__result"
               exit 1
            fi
            __status=$(echo "$__result" | jq -r '.data[].status')
            case ${__status,,} in
                error)
                    echo "An error was encountered trying to register the key $__pubkey:"
                    echo "$__result" | jq -r '.data[].message'
                    echo
                    (( __reg_errored+=1 ))
                    ;;
                imported)
                    echo "Validator key was successfully registered with validator client: $__pubkey"
                    echo
                    (( __registered+=1 ))
                    ;;
                duplicate)
                    echo "Validator key is a duplicate and registration was skipped: $__pubkey"
                    echo
                    (( __reg_skipped+=1 ))
                    ;;
                *)
                    echo "Unexpected status $__status. This may be a bug"
                    exit 1
                    ;;
            esac
        fi
        echo
    done

    echo "Imported $__imported keys"
    if [ "$WEB3SIGNER" = "true" ]; then
        echo "Registered $__registered keys with the validator client"
    fi
    echo "Skipped $__skipped keys"
    if [ "$WEB3SIGNER" = "true" ]; then
        echo "Skipped registration of $__reg_skipped keys"
    fi
    if [ $__errored -gt 0 ]; then
        echo "$__errored keys caused an error during import"
    fi
    if [ $__reg_errored -gt 0 ]; then
        echo "$__reg_errored keys caused an error during registration"
    fi
    echo
    echo "IMPORTANT: Only import keys in ONE LOCATION."
    echo "Failure to do so will get your validators slashed: Greater 1 ETH penalty and forced exit."
}

validator-register() {
    if [ ! "${WEB3SIGNER}" = "true" ]; then
        echo "WEB3SIGNER is not \"true\" in .env, cannot register web3signer keys with the validator client."
        echo "Aborting."
        exit 1
    fi

    __api_path=eth/v1/keystores
    __token=NIL
    __vc_api_container=${__api_container}
    __api_container=web3signer
    __vc_api_port=${__api_port}
    __api_port=9000
    __vc_api_tls=${__api_tls}
    __api_tls=false
    __validator-list-call
    if [ "$(echo "$__result" | jq '.data | length')" -eq 0 ]; then
        echo "No keys loaded in web3signer, aborting."
        exit 1
    fi

    __api_container=${__vc_api_container}
    __api_port=${__vc_api_port}
    __api_tls=${__vc_api_tls}
    get-token
    __registered=0
    __reg_skipped=0
    __reg_errored=0

    __w3s_pubkeys="$(echo "$__result" | jq -r '.data[].validating_pubkey')"
    while IFS= read -r __pubkey; do
        jq --arg pubkey_value "$__pubkey" --arg url_value "http://web3signer:9000" '. | .remote_keys += [{"pubkey": $pubkey_value, "url": $url_value}]' <<< '{}' >/tmp/apidata.txt

        __api_data=@/tmp/apidata.txt
        __api_path=eth/v1/remotekeys
        __http_method=POST
        call_api
        case $__code in
            200) ;;
            401) echo "No authorization token found. This is a bug. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            403) echo "The authorization token is invalid. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            500) echo "Internal server error. Error: $(echo "$__result" | jq -r '.message')"; exit 1;;
            *) echo "Unexpected return code $__code. Result: $__result"; exit 1;;
        esac
        if ! echo "$__result" | grep -q "data"; then
           echo "The key manager API query failed. Output:"
           echo "$__result"
           exit 1
        fi
        __status=$(echo "$__result" | jq -r '.data[].status')
        case ${__status,,} in
            error)
                echo "An error was encountered trying to register the key $__pubkey:"
                echo "$__result" | jq -r '.data[].message'
                echo
                (( __reg_errored+=1 ))
                ;;
            imported)
                echo "Validator key was successfully registered with validator client: $__pubkey"
                echo
                (( __registered+=1 ))
                ;;
            duplicate)
                echo "Validator key is a duplicate and registration was skipped: $__pubkey"
                echo
                (( __reg_skipped+=1 ))
                ;;
            *)
                echo "Unexpected status $__status. This may be a bug"
                exit 1
                ;;
        esac
    done <<< "${__w3s_pubkeys}"

    echo "Registered $__registered keys with the validator client"
    echo "Skipped registration of $__reg_skipped keys"
    if [ $__reg_errored -gt 0 ]; then
        echo "$__reg_errored keys caused an error during registration"
    fi
    echo
}

# Verify keys only exist in one location
__web3signer_check() {
    if [[ -z "${PRYSM:+x}" && ! "${WEB3SIGNER}" = "true" ]]; then
        get-token
        __api_path=eth/v1/remotekeys
        __validator-list-call
        if [ ! "$(echo "$__result" | jq '.data | length')" -eq 0 ]; then
            echo "WEB3SIGNER is not \"true\" in .env, but there are web3signer keys registered."
            echo "This is not safe. Set WEB3SIGNER=true and remove web3signer keys first. Aborting."
            exit 1
        fi
    fi
}

usage() {
    echo "Call keymanager with an ACTION, one of:"
    echo "  list"
    echo "     Lists the public keys of all validators currently loaded into your validator client"
    echo "  import"
    echo "      Import all keystore*.json in .eth/validator_keys while loading slashing protection data"
    echo "      in slashing_protection*.json files that match the public key(s) of the imported validator(s)"
    echo "  delete 0xPUBKEY | all"
    echo "      Deletes the validator with public key 0xPUBKEY from the validator client, and exports its"
    echo "      slashing protection database. \"all\" deletes all detected validators instead"
    echo "  register"
    echo "      For use with web3signer only: Re-register all keys in web3signer with the validator client"
    echo
    echo "  get-recipient 0xPUBKEY"
    echo "      List fee recipient set for the validator with public key 0xPUBKEY"
    echo "      Validators will use FEE_RECIPIENT in .env by default, if not set individually"
    echo "  set-recipient 0xPUBKEY 0xADDRESS"
    echo "      Set individual fee recipient for the validator with public key 0xPUBKEY"
    echo "  delete-recipient 0xPUBKEY"
    echo "      Delete individual fee recipient for the validator with public key 0xPUBKEY"
    echo
    echo "  get-gas 0xPUBKEY"
    echo "      List execution gas limit set for the validator with public key 0xPUBKEY"
    echo "      Validators will use the client's default, if not set individually"
    echo "  set-gas 0xPUBKEY amount"
    echo "      Set individual execution gas limit for the validator with public key 0xPUBKEY"
    echo "  delete-gas 0xPUBKEY"
    echo "      Delete individual execution gas limit for the validator with public key 0xPUBKEY"
    echo
    echo "  get-api-token"
    echo "      Print the token for the keymanager API running on port ${__api_port}."
    echo "      This is also the token for the Prysm Web UI"
    echo
    echo "  create-prysm-wallet"
    echo "      Create a new Prysm wallet to store keys in"
    echo "  get-prysm-wallet"
    echo "      Print Prysm's wallet password"
    echo
    echo "  prepare-address-change"
    echo "      Create an offline-preparation.json with ethdo"
    echo "  send-address-change"
    echo "      Send a change-operations.json with ethdo, setting the withdrawal address"
    echo
    echo "  sign-exit from-keystore [--offline]"
    echo "      Create pre-signed exit messages with ethdo, from keystore files in ./.eth/validator_keys"
}

set -e

if [ "$(id -u)" = '0' ]; then
    __token_file=$1
    __api_container=$2
    __api_port=${KEY_API_PORT:-7500}
    if [ -z "${TLS:+x}" ]; then
        __api_tls=false
    else
        __api_tls=true
    fi
    case "$3" in
        get-api-token)
            print-api-token
            exit 0
            ;;
        create-prysm-wallet)
            echo "There's a bug in ethd; this command should have been handled one level higher. Please report this."
            exit 1
            ;;
        get-prysm-wallet)
            get-prysm-wallet
            exit 0
            ;;
    esac
    if [ -z "$3" ]; then
        usage
        exit 0
    fi
    if [ -f "$__token_file" ]; then
        cp "$__token_file" /tmp/api-token.txt
        chown "${OWNER_UID:-1000}":"${OWNER_UID:-1000}" /tmp/api-token.txt
        exec gosu "${OWNER_UID:-1000}":"${OWNER_UID:-1000}" "${BASH_SOURCE[0]}" "$@"
    else
        echo "File $__token_file not found."
        echo "The $__api_container service may not be fully started yet."
        exit 1
    fi
fi
__token_file=/tmp/api-token.txt
__api_container=$2
__api_port=${KEY_API_PORT:-7500}
if [ -z "${TLS:+x}" ]; then
    __api_tls=false
else
    __api_tls=true
fi

case "$3" in
    list)
        validator-list
        ;;
    delete)
        __pubkey=$4
        validator-delete
        ;;
    import)
        __web3signer_check
        shift 3
        validator-import "$@"
        ;;
    register)
        validator-register
        ;;
    get-recipient)
        __pubkey=$4
        recipient-get
        ;;
    set-recipient)
        __pubkey=$4
        __address=$5
        recipient-set
        ;;
    delete-recipient)
        __pubkey=$4
        recipient-delete
        ;;
    get-gas)
        __pubkey=$4
        gas-get
        ;;
    set-gas)
        __pubkey=$4
        __limit=$5
        gas-set
        ;;
    delete-gas)
        __pubkey=$4
        gas-delete
        ;;
    prepare-address-change)
        echo "This should have been handled one layer up in ethd. This is a bug, please report."
        ;;
    send-address-change)
        echo "This should have been handled one layer up in ethd. This is a bug, please report."
        ;;
    *)
        usage
        ;;
esac
