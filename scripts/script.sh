#!/bin/bash

DELAY="$1"
TIMEOUT="$2"
VERBOSE="$3"
MAX_RETRY="$4"
# shellcheck disable=SC2223
: ${DELAY:="3"}
# shellcheck disable=SC2223
: ${TIMEOUT:="10"}
# shellcheck disable=SC2223
: ${VERBOSE:="false"}
# shellcheck disable=SC2223
: ${MAX_RETRY:="false"}

# import utils
. scripts/utils.sh

parsePeerConnectionParameters() {
  PEER_CONN_PARAMS=""
  PEERS=""
  while [ "$#" -gt 0 ]; do
    setGlobals $1
    PEER="peer0.${CORE_PEER_LOCALMSPID}.example.com"
    ## Set peer addresses
    PEERS="$PEERS $PEER"
    PEER_CONN_PARAMS="${PEER_CONN_PARAMS} --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles ${CORE_PEER_TLS_ROOTCERT_FILE}"
    shift
  done
  PEERS="$(echo -e "$PEERS" | sed -e 's/^[[:space:]]*//')"
}

createChannel() {
  local channel=$1
  local org=$2

  setGlobals "${org}"

  set -x
  peer channel create -o orderer.example.com:7050 -c "$channel" -f ./fixtures/channel-artifacts/"${channel}".tx --tls "${CORE_PEER_TLS_ENABLED}" --cafile "${ORDERER_CA}" >&log.txt
  res=$?
  set +x
  cat log.txt
  verifyResult $res "${channel} channel creation failed"

  echo ">>> channel '$channel' created"
}

joinChannel() {
  local channel=$1
  local org=$2

  setGlobals "${org}"

  peer channel join -b "${channel}".block >&log.txt

  verifyResult $res "error joining org ${org} to the channel ${channel}"

  echo ">>> org ${org} joined to the channel ${channel}"
}

updateAnchorPeers() {
  local channel=$1
  local org=$2

  setGlobals "${org}"

  set -x
  peer channel update -o orderer.example.com:7050 -c "${channel}" -f ./fixtures/channel-artifacts/"${org}"-anchor-"${channel}".tx --tls --cafile "${ORDERER_CA}" >&log.txt
  res=$?
  set +x
  cat log.txt

  verifyResult $res "anchor peer update failed"
  echo ">>> anchor peer from org ${org} updated for the channel ${channel}"
}

packageChaincode() {
  local name=$1
  local version=$2
  local org=$3

  setGlobals "${org}"

  peer lifecycle chaincode package "${name}"_"${version}".tar.gz --path "${CC_SRC_PATH}"/"${name}" --lang "${CC_RUNTIME_LANGUAGE}" --label "${name}"_"${version}" >&log.txt
  res=$?
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

queryInstalled() {
  local org=$1

  setGlobals "${org}"

  peer lifecycle chaincode queryinstalled >&log.txt
  res=$?
  cat log.txt
  verifyResult $res "query installed for org ${org} has failed"
  echo ">>> query installed successful for org ${org} on channel"
}

approveChaincode() {
  local channel=$1
  local name=$2
  local org=$3
  local version=$4

  setGlobals "${org}"

  peer lifecycle chaincode queryinstalled >&log.txt
  PACKAGE_ID=$(sed -n "/${name}_${version}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
  echo "${PACKAGE_ID}"

  peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" --version "${version}" --package-id "${PACKAGE_ID}" --sequence 1 >&log.txt
  cat log.txt

  peer lifecycle chaincode checkcommitreadiness --channelID "${channel}" --name "${name}" --version "${version}" --sequence 1 --output json >&log.txt
  cat log.txt

  res=$?
  verifyResult $res "chaincode definition approved for org ${org} in channel ${channel} failed"
  echo ">>> chaincode definition approved for org ${org} in channel ${channel}"
}

lifecycleCommitChaincodeDefinition() {
  local channel=$1
  local name=$2
  local org=$3
  local version=$4
  shift 4

  parsePeerConnectionParameters $@

  setGlobals "${org}"

  peer lifecycle chaincode commit -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" --version "${version}" --sequence 1 $PEER_CONN_PARMS >&log.txt
  res=$?

  verifyResult $res "chaincode definition commit failed for org ${org} on channel '${channel}' failed"
  echo ">>> chaincode definition committed on channel '${channel}'"
}

chaincodeInvoke() {
  local channel=$1
  local name=$2
  local org=$3
  local args=$4
  shift 4

  parsePeerConnectionParameters $@

  setGlobals "${org}"

  set -x
  peer chaincode invoke -o orderer.example.com:7050 --tls --cafile "${ORDERER_CA}" --channelID "${channel}" --name "${name}" -c "${args}" $PEER_CONN_PARMS >&log.txt
  res=$?
  set +x
  cat log.txt

  verifyResult $res "invoke execution on ${CORE_PEER_ADDRESS} failed "
  echo ">>> invoke transaction successful on ${CORE_PEER_ADDRESS} on channel '${channel}'"
}

echo ">>> creating global channel..."
# channel org
createChannel global auditor
echo ">>> done..."

echo

echo ">>> joining peers to the channels..."
# channel org
joinChannel global auditor
echo ">>> done..."

echo

echo ">>> updating anchor peers for channels..."
# channel org
updateAnchorPeers global auditor
echo ">>> done..."

echo ">>> packaging 'registration' chaincode..."
# chaincode_name version org
packageChaincode registration 1 auditor
# chaincode_name org version
installChaincode registration auditor 1
# org
queryInstalled auditor
# channel_name chaincode_version org version
approveChaincode global registration auditor 1
# channel_name chaincode_name org version @peers
lifecycleCommitChaincodeDefinition global registration auditor 1 auditor
# channel_name chaincode_name org args @peers
chaincodeInvoke global registration auditor '{"function":"Register","Args":["auditor"]}' auditor

echo

exit 0
