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

parsePeerConnectionParameters() {
  PEER_CONN_PARAMS=""
  PEERS=""
  while [ "$#" -gt 0 ]; do
    echo $1
    setGlobals $1
    PEER="peer0.${CORE_PEER_LOCALMSPID}.example.com"
    ## Set peer addresses
    PEERS="$PEERS $PEER"
    PEER_CONN_PARAMS="${PEER_CONN_PARAMS} --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles ${CORE_PEER_TLS_ROOTCERT_FILE}"
    shift
  done
  PEERS="$(echo -e "$PEERS" | sed -e 's/^[[:space:]]*//')"
}

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
  res=$?
  verifyResult $res
  { set +x; } 2>/dev/null
}

# listChannelWithRetry <organization>
# Join to the channel6 but before checking available channels
listChannelWithRetry() {
  local ORG=$1

  setGlobals "${ORG}"

  # get channel list
  set -x
  peer channel list >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt

  if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
    COUNTER=$(expr $COUNTER + 1)
    echo "peer0.${ORG}.example.com failed to list channels, retry after $DELAY seconds"
    sleep $DELAY
    listChannelWithRetry "${ORG}"
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer0.${ORG} has failed to list channels"
}

# joinChannel <organization> <channel>
joinChannel() {
  local ORG=$1

  setGlobals "${ORG}"

  set -x
  peer channel join -b "${CHANNEL}".block >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "peer0.${ORG} has failed to join channel '$CHANNEL' "
}

# packageChaincode <organization> <chaincode_name> <chaincode_version>
# more:  https://hyperledger-fabric.readthedocs.io/en/release-2.2/chaincode_lifecycle.htmll#step-one-packaging-the-smart-contract
packageChaincode() {
  local org=$1
  local name=$2
  local version=$3

  setGlobals "${org}"

  set -x
  peer lifecycle chaincode package "${name}"_"${version}".tar.gz --path "${CC_SRC_PATH}"/"${name}" --lang "${CC_RUNTIME_LANGUAGE}" --label "${name}"_"${version}" >&log.txt
  set +x
  res=$?
  cat log.txt
  verifyResult $res "chaincode packaging by org ${ORG} has failed"
  echo ">>> chaincode is packaged by org ${org}"
}

# installChaincode <organization> <chaincode_name> <chaincode_version>
# more:  https://hyperledger-fabric.readthedocs.io/en/release-2.2/chaincode_lifecycle.html#step-two-install-the-chaincode-on-your-peers
installChaincode() {
  local org=$1
  local name=$2
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

# checkCommitReadiness <channel_name> <chaincode_name> <organization> <chaincode_version>
# Command to check whether committing the chaincode definition should be successful
# based on which channel members have approved a definition before committing it to the channel
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

# approveChaincode <channel_name> <chaincode_name> <organization> <chaincode_version>
# These approved organization definitions allow channel members to agree on a chaincode before it can be used on a channel.
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
  peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" --version "${version}" --package-id "${PACKAGE_ID}" --sequence 1 >&log.txt
  set +x
  cat log.txt

  res=$?
  verifyResult $res "chaincode definition approved for org ${org} in channel ${channel} failed"
  echo ">>> chaincode definition approved for org ${org} in channel ${channel}"
}

# queryInstalled <organization>
# Query the installed chaincodes on a peer.
queryInstalled() {
  ORG=$1

  setGlobals $ORG

  set -x
  peer lifecycle chaincode queryinstalled >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt

  PACKAGE_ID=$(sed -n "/${CC_NAME}_${CC_VERSION}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
  verifyResult $res "Query installed on peer0.org${ORG} has failed"
  successln "Query installed successful on peer0.org${ORG} on channel"
}

# lifecycleCommitChaincodeDefinition <channel_name> <chaincode_name> <organization> <chaincode_version>
# Once a sufficient number of organizations approve a chaincode definition for their organizations (a majority by default),
# one organization can commit the definition the channel
lifecycleCommitChaincodeDefinition() {
  local channel=$1
  local name=$2
  local org=$3
  local version=$4
  shift 4

  # function got all connection parameters, concatenate it into single string
  # and save it into $PEER_CONN_PARAMS variable
  parsePeerConnectionParameters $@

  setGlobals "${org}"

  set -x
  peer lifecycle chaincode commit -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" --version "${version}" --sequence 2 $PEER_CONN_PARAMS >&log.txt
  res=$?
  set +x
  cat log.txt

  verifyResult $res "chaincode definition commit failed for org ${org} on channel '${channel}' failed"
  echo ">>> chaincode definition committed on channel '${channel}'"
}

# chaincodeInvoke <channel_name> <chaincode_name> <organization> <arguments>
chaincodeInvoke() {
  local channel=$1
  local name=$2
  local org=$3
  local args=$4
  shift 4

  # function got all connection parameters, concatenate it into single string
  # and save it into $PEER_CONN_PARAMS variable
  parsePeerConnectionParameters $@

  setGlobals "${org}"

  set -x
  peer chaincode invoke -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" -c "${args}" $PEER_CONN_PARAMS >&log.txt
  res=$?
  set +x
  cat log.txt

  verifyResult $res "invoke execution on ${CORE_PEER_ADDRESS} failed "
  echo ">>> invoke transaction successful on ${CORE_PEER_ADDRESS} on channel '${channel}'"
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

# calculate organizations for sign
# binary file for calculating was copied into folder below (you can check it in CLI container)
cd /opt/gopath/src/github.com/hyperledger/fabric/peer/bin/
# run the binary thats calculate organizations in the channel
./main
cd ..

WHITESPACE=" "
input="/opt/gopath/src/github.com/hyperledger/fabric/peer/channel_orgs.txt"
while IFS= read -r line
do
  CHANNEL_ORGS="${CHANNEL_ORGS}""${WHITESPACE}""${line}"
  if [[ $line == "auditor" ]]; then
     continue
  fi
  signConfigtxAsPeerOrg $line org_update_in_envelope.pb
done <"$input"

bn=$(getBlockNumber auditor "${CHANNEL}")

setGlobals auditor
set -x
peer channel update -f org_update_in_envelope.pb -o orderer.example.com:7050 -c "${CHANNEL}" --tls --cafile "${ORDERER_CA}"
set +x

echo ">>> config transaction to add $ORGANIZATION to ${CHANNEL} submitted!.."

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

check_with_backoff auditor "${CHANNEL}" "${bn}"

listChannelWithRetry $ORGANIZATION
joinChannel $ORGANIZATION

# org chaincode_name chaincode_version
packageChaincode $ORGANIZATION registration 1
# org chaincode_name chaincode_version
installChaincode $ORGANIZATION registration 1

queryInstalled $ORGANIZATION

# channel_name chaincode_name org chaincode_version
approveChaincode global registration $ORGANIZATION 1

chaincodeInvoke global registration $ORGANIZATION '{"function":"Register","Args":["'$ORGANIZATION'"]}' $ORGANIZATION $CHANNEL_ORGS

echo ">>> done..."

exit 0

