COUNTER=1
MAX_RETRY=5
PACKAGE_ID=""

CC_RUNTIME_LANGUAGE=golang
CC_SRC_PATH="/opt/gopath/src/chaincode"

export CORE_PEER_TLS_ENABLED=true

ORDERER_CA=${PWD}/fixtures/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
PEER0_AUDITOR_CA=${PWD}/fixtures/organizations/peerOrganizations/auditor.example.com/peers/peer0.auditor.example.com/tls/ca.crt

declare -A MSP
MSP[1]="auditor"
MSP[2]="org1"
MSP[3]="org2"
MSP[4]="org3"

# verify the result of the end-to-end test
verifyResult() {
  if [ $1 -ne 0 ]; then
    echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    echo "========= ERROR !!! FAILED to execute End-2-End Scenario ==========="
    echo
    exit 1
  fi
}

# Set ExampleCom.Admin globals
setOrdererGlobals() {
  CORE_PEER_LOCALMSPID="orderer"
  CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/fixtures/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
  CORE_PEER_MSPCONFIGPATH=${PWD}/fixtures/organizations/ordererOrganizations/example.com/users/Admin@example.com/msp
}

setGlobals() {
  local org=$1
  if [[ "${org}" == "auditor" ]]; then
    CORE_PEER_LOCALMSPID="auditor"
    CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_AUDITOR_CA
    CORE_PEER_MSPCONFIGPATH=${PWD}/fixtures/organizations/peerOrganizations/auditor.example.com/users/Admin@auditor.example.com/msp
    CORE_PEER_ADDRESS=peer0.auditor.example.com:7051
  elif [[ "${org}" == "org"* ]]; then
    CORE_PEER_LOCALMSPID=${org}
    CORE_PEER_TLS_ROOTCERT_FILE=${PWD}/fixtures/organizations/peerOrganizations/${org}.example.com/peers/peer0.${org}.example.com/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=${PWD}/fixtures/organizations/peerOrganizations/${org}.example.com/users/Admin@${org}.example.com/msp
    PORT=$(expr "${org:3}" + 7)
    CORE_PEER_ADDRESS=peer0.${org}.example.com:${PORT}051
  else
    echo "${org}"
    echo ">>> error: unknown organization"
  fi
}

parsePeerConnectionParameters() {
  PEER_CONN_PARMS=""
  PEERS=""
  while [ "$#" -gt 0 ]; do
    setGlobals $1
    PEER="peer0.${CORE_PEER_LOCALMSPID}.example.com"
    ## Set peer addresses
    PEERS="$PEERS $PEER"
    PEER_CONN_PARMS="${PEER_CONN_PARMS} --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles ${CORE_PEER_TLS_ROOTCERT_FILE}"
    shift
  done
  PEERS="$(echo -e "$PEERS" | sed -e 's/^[[:space:]]*//')"
}
