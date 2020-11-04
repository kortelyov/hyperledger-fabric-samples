#!/bin/bash

ORGANIZATION="$1"
CHANNEL="$2"
DELAY="$3"
TIMEOUT="$4"
VERBOSE="$5"
# shellcheck disable=SC2223
: ${ORGANIZATION:="organization"}
# shellcheck disable=SC2223
: ${CHANNEL:="channel"}
# shellcheck disable=SC2223
: ${DELAY:="3"}
# shellcheck disable=SC2223
: ${TIMEOUT:="10"}
# shellcheck disable=SC2223
: ${VERBOSE:="false"}

. scripts/utils.sh

# fetchChannelConfig <channel_id> <output_json>
# Writes the current channel config for a given channel to a JSON file
fetchChannelConfig() {
  OUTPUT=$1

  setOrdererGlobals

  echo ">>> fetching the most recent configuration block for the ${CHANNEL} channel"

  set -x
  peer channel fetch config config_block.pb -o orderer.example.com:7050 -c "${CHANNEL}" --tls --cafile "${ORDERER_CA}"
  { set +x; } 2>/dev/null

  echo ">>> decoding config block to JSON and isolating config to ${OUTPUT}"
  set -x
  configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config >"${OUTPUT}"
  set +x
}

# createConfigUpdate <original_config.json> <modified_config.json> <output.pb>
# Takes an original and modified config, and produces the config update tx
# which transitions between the two
createConfigUpdate() {
  ORIGINAL=$1
  MODIFIED=$2
  OUTPUT=$3

  set -x
  configtxlator proto_encode --input "${ORIGINAL}" --type common.Config >original_config.pb
  configtxlator proto_encode --input "${MODIFIED}" --type common.Config >modified_config.pb
  configtxlator compute_update --channel_id "${CHANNEL}" --original original_config.pb --updated modified_config.pb >config_update.pb
  configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate | jq . >config_update.json
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'${CHANNEL}'","type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . >config_update_in_envelope.json
  configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope >"${OUTPUT}"
  set +x
}

signConfigtxAsPeerOrg() {
  local TX=$1

  setOrdererGlobals
  set -x
  peer channel signconfigtx -f "${TX}"
  { set +x; } 2>/dev/null
}

echo ">>> creating config transaction to add $ORGANIZATION to the $CHANNEL channel..."

# Fetch the config for the channel, writing it to config.json
fetchChannelConfig config.json

# Modify the configuration to append the new organization
set -x
jq -s '.[0] * {"channel_group":{"groups":{"Consortiums":{"groups":{"GlobalConsortium":{"groups": {"'$ORGANIZATION'":.[1]}}}}}}}' config.json ./fixtures/organizations/peerOrganizations/$ORGANIZATION.example.com/$ORGANIZATION.json > modified_config.json
set +x

# Compute a config update, based on the differences between config.json and modified_config.json,
# write it as a transaction to org_update_in_envelope.pb
createConfigUpdate config.json modified_config.json org_update_in_envelope.pb

signConfigtxAsPeerOrg org_update_in_envelope.pb

setOrdererGlobals

set -x
peer channel update -f org_update_in_envelope.pb -o orderer.example.com:7050 -c "${CHANNEL}" --tls --cafile "${ORDERER_CA}"
set +x

echo ">>> config transaction to add $ORGANIZATION to ${CHANNEL} submitted!.."

setOrdererGlobals

set -x
peer channel fetch config config_block_sys_update.pb -o orderer.example.com:7050 -c "${CHANNEL}" --tls --cafile "${ORDERER_CA}"
res=$?
verifyResult $res
{ set +x; } 2>/dev/null

echo ">>> done..."

exit 0
