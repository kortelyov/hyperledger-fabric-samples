#!/bin/bash

ORGANIZATION="$1"
CHANNEL="$2"
DELAY="$3"
TIMEOUT="$4"
VERBOSE="$5"
# shellcheck disable=SC2223
: ${ORGANIZATION:="organization"}
# shellcheck disable=SC2223
: ${CHANNEL:="global"}
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

# signConfigtxAsPeerOrg <org> <configtx.pb>
# Set the peerOrg admin of an org and signing the config update
signConfigtxAsPeerOrg() {
  local ORG=$1
  local TX=$2

  setGlobals "${ORG}"
  set -x
  echo "signConfigtxAsPeerOrg by $ORG organization"
  peer channel signconfigtx -f "${TX}"
  verifyResult $res
  { set +x; } 2>/dev/null
}

joinChannelWithRetry() {
  local ORG=$1

  setGlobals "${ORG}"

  echo ">>> channels list:"
  peer channel list

  set -x
  peer channel join -b "${CHANNEL}".block >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt

  if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
    COUNTER=$(expr $COUNTER + 1)
    echo "peer0.${ORG}.example.com failed to join the ${CHANNEL} channel, retry after $DELAY seconds"
    sleep $DELAY
    joinChannelWithRetry "${ORG}"
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer0.${ORG} has failed to join channel '$CHANNEL' "
}

packageChaincode() {
  local name=$1
  local version=$2
  local org=$3

  setGlobals "${org}"

  set -x
  peer lifecycle chaincode package "${name}"_"${version}".tar.gz --path "${CC_SRC_PATH}"/"${name}" --lang "${CC_RUNTIME_LANGUAGE}" --label "${name}"_"${version}" >&log.txt
  set +x
  res=$?
  cat log.txt
  verifyResult $res "chaincode packaging by org ${ORG} has failed"
  echo ">>> chaincode is packaged by org ${org}"
}

installChaincode() {
  local name=$1
  local org=$2
  local version=$3

  setGlobals "${org}"

  set -x
  peer lifecycle chaincode install "${name}"_"${version}".tar.gz >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt

  verifyResult $res "chaincode installation on org ${org} has failed"
  echo ">>> chaincode ${name} is installed on org ${org}"
}

checkCommitReadiness() {
  local channel=$1
  local name=$2
  local org=$3
  local version=$4

  setGlobals "${org}"

  set -x
  peer lifecycle chaincode checkcommitreadiness --channelID "${channel}" --name "${name}" --version "${version}" --sequence 2 --output json
  set +x
  res=$?

  verifyResult $res "Chaincode checkCommitReadiness failed for org ${org} on channel '${channel}' failed"
}

approveChaincode() {
  local channel=$1
  local name=$2
  local org=$3
  local version=$4

  setGlobals "${org}"

  set -x
  peer lifecycle chaincode queryinstalled >&log.txt
  PACKAGE_ID=$(sed -n "/${name}_${version}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
  echo "${PACKAGE_ID}"
  set +x
  cat log.txt

  set -x
  peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" --version "${version}" --package-id "${PACKAGE_ID}" --sequence 2 >&log.txt
  set +x
  cat log.txt

  set -x
  peer lifecycle chaincode checkcommitreadiness --channelID "${channel}" --name "${name}" --version "${version}" --sequence 2 --output json >&log.txt
  set +x
  cat log.txt

  res=$?
  verifyResult $res "chaincode definition approved for org ${org} in channel ${channel} failed"
  echo ">>> chaincode definition approved for org ${org} in channel ${channel}"
}

echo ">>> creating config transaction to add $ORGANIZATION to the $CHANNEL channel..."

# Fetch the config for the channel, writing it to config.json
fetchChannelConfig config.json

# Modify the configuration to append the new organization
set -x
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"'$ORGANIZATION'":.[1]}}}}}' config.json ./fixtures/organizations/peerOrganizations/$ORGANIZATION.example.com/$ORGANIZATION.json > modified_config.json
set +x

# Compute a config update, based on the differences between config.json and modified_config.json,
# write it as a transaction to org_update_in_envelope.pb
createConfigUpdate config.json modified_config.json org_update_in_envelope.pb

signConfigtxAsPeerOrg auditor org_update_in_envelope.pb

#setOrdererGlobals

setGlobals auditor
set -x
peer channel update -f org_update_in_envelope.pb -o orderer.example.com:7050 -c "${CHANNEL}" --tls --cafile "${ORDERER_CA}"
set +x

echo ">>> config transaction to add $ORGANIZATION to ${CHANNEL} submitted!.."


#setGlobals $ORGANIZATION
#setOrdererGlobals
echo
echo ">>> fetching ${CHANNEL} channel config block from orderer..."
echo

setGlobals $ORGANIZATION
set -x
peer channel fetch 0 "${CHANNEL}".block -o orderer.example.com:7050 -c "${CHANNEL}" --tls --cafile "${ORDERER_CA}" >&log.txt
res=$?
{ set +x; } 2>/dev/null
cat log.txt

echo "$res"
verifyResult $res ">>> fetching config block from orderer has failed"

#joinChannelWithRetry $ORGANIZATION

# chaincode_version version org
#packageChaincode registration 1 org1
# chaincode_version org version
#installChaincode registration org1 1

sleep 10

# channel name org version
checkCommitReadiness global registration auditor 1
approveChaincode global registration auditor 1
#checkCommitReadiness global registration auditor 1
approveChaincode global registration org1 1
#checkCommitReadiness global registration auditor 1


#queryInstalled 2
#approveChaincode verizon localdata 2 1
#lifecycleCommitChaincodeDefinition verizon localdata 2 1 2
#initLedger verizon localdata "http://ecsa00401079.epam.com:8093" 2

echo ">>> done..."

exit 0
