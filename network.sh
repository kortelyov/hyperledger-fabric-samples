#!/bin/bash

export PATH=${PWD}/../bin:$PATH
export FABRIC_CFG_PATH=${PWD}/configtx
export VERBOSE=false

function printHelp() {
  echo "Usage: "
  echo "  network.sh <Mode> [Flags]"
  echo "    Modes:"
  echo "      "$'\e[0;32m'up$'\e[0m' - bring up fabric orderer and peer nodes. No channel is created
  echo "      "$'\e[0;32m'up createChannel$'\e[0m' - bring up fabric network with one channel
  echo "      "$'\e[0;32m'createChannel$'\e[0m' - create and join a channel after the network is created
  echo "      "$'\e[0;32m'deployCC$'\e[0m' - deploy the asset transfer basic chaincode on the channel or specify
  echo "      "$'\e[0;32m'down$'\e[0m' - clear the network with docker-compose down
  echo "      "$'\e[0;32m'restart$'\e[0m' - restart the network
  echo
  echo "    Flags:"
  echo "    Used with "$'\e[0;32m'network.sh up$'\e[0m', $'\e[0;32m'network.sh createChannel$'\e[0m':
  echo "    -ca <use CAs> -  create Certificate Authorities to generate the crypto material"
  echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
  echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
  echo "    -r <max retry> - CLI times out after certain number of attempts (defaults to 5)"
  echo "    -d <delay> - delay duration in seconds (defaults to 3)"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -cai <ca_imagetag> - the image tag to be used for CA (defaults to \"${CA_IMAGETAG}\")"
  echo "    -verbose - verbose mode"
  echo "    Used with "$'\e[0;32m'network.sh deployCC$'\e[0m'
  echo "    -c <channel name> - deploy chaincode to channel"
  echo "    -ccn <name> - the short name of the chaincode to deploy: basic (default),ledger, private, sbe, secured"
  echo "    -ccl <language> - the programming language of the chaincode to deploy: go (default), java, javascript, typescript"
  echo "    -ccv <version>  - chaincode version. 1.0 (default)"
  echo "    -ccs <sequence>  - chaincode definition sequence. Must be an integer, 1 (default), 2, 3, etc"
  echo "    -ccp <path>  - Optional, path to the chaincode. When provided the -ccn will be used as the deployed name and not the short name of the known chaincodes."
  echo "    -ccep <policy>  - Optional, chaincode endorsement policy, using signature policy syntax. The default policy requires an endorsement from Org1 and Org2"
  echo "    -cccg <collection-config>  - Optional, path to a private data collections configuration file"
  echo "    -cci <fcn name>  - Optional, chaincode init required function to invoke. When provided this function will be invoked after deployment of the chaincode and will define the chaincode as initialization required."
  echo
  echo "    -h - print this message"
  echo
  echo " Possible Mode and flag combinations"
  echo "   "$'\e[0;32m'up$'\e[0m' -ca -c -r -d -s -i -verbose
  echo "   "$'\e[0;32m'up createChannel$'\e[0m' -ca -c -r -d -s -i -verbose
  echo "   "$'\e[0;32m'createChannel$'\e[0m' -c -r -d -verbose
  echo "   "$'\e[0;32m'deployCC$'\e[0m' -ccn -ccl -ccv -ccs -ccp -cci -r -d -verbose
  echo
  echo " Taking all defaults:"
  echo "   network.sh up"
  echo
  echo " Examples:"
  echo "   network.sh up createChannel -ca -c mychannel -s couchdb -i 2.0.0"
  echo "   network.sh createChannel -c channelName"
  echo "   network.sh deployCC -ccn basic -ccl javascript"
  echo "   network.sh deployCC -ccn mychaincode -ccp ./user/mychaincode -ccv 1 -ccl javascript"
}

function clearContainers() {
  CONTAINER_IDS=$(docker ps -a | awk '($2 ~ /dev-peer.*/) {print $1}')
  if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
    echo "---- No containers available for deletion ----"
  else
    docker rm -f $CONTAINER_IDS
  fi
}

function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "---- No images available for deletion ----"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

# Versions of fabric known not to work with the test network
NONWORKING_VERSIONS="^1\.0\. ^1\.1\. ^1\.2\. ^1\.3\. ^1\.4\."

function checkPrereqs() {
  peer version > /dev/null 2>&1

#  if [[ $? -ne 0 || ! -d "../config" ]]; then
#    echo "ERROR! Peer binary and configuration files not found.."
#    echo
#    echo "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
#    echo "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
#    exit 1
#  fi
  # use the fabric tools container to see if the samples and binaries match your
  # docker images
  LOCAL_VERSION=$(peer version | sed -ne 's/ Version: //p')
  DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-tools:$IMAGETAG peer version | sed -ne 's/ Version: //p' | head -1)

  echo "LOCAL_VERSION=$LOCAL_VERSION"
  echo "DOCKER_IMAGE_VERSION=$DOCKER_IMAGE_VERSION"

  if [ "$LOCAL_VERSION" != "$DOCKER_IMAGE_VERSION" ]; then
    echo "=================== WARNING ==================="
    echo "  Local fabric binaries and docker images are  "
    echo "  out of  sync. This may cause problems.       "
    echo "==============================================="
  fi

  for UNSUPPORTED_VERSION in $NONWORKING_VERSIONS; do
    echo "$LOCAL_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      echo "ERROR! Local Fabric binary version of $LOCAL_VERSION does not match the versions supported by the test network."
      exit 1
    fi

    echo "$DOCKER_IMAGE_VERSION" | grep -q $UNSUPPORTED_VERSION
    if [ $? -eq 0 ]; then
      echo "ERROR! Fabric Docker image version of $DOCKER_IMAGE_VERSION does not match the versions supported by the test network."
      exit 1
    fi
  done

  ## Check for fabric-ca
  if [ "$CRYPTO" == "Certificate Authorities" ]; then

    fabric-ca-client version > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      echo "ERROR! fabric-ca-client binary not found.."
      echo
      echo "Follow the instructions in the Fabric docs to install the Fabric Binaries:"
      echo "https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
      exit 1
    fi
    CA_LOCAL_VERSION=$(fabric-ca-client version | sed -ne 's/ Version: //p')
    CA_DOCKER_IMAGE_VERSION=$(docker run --rm hyperledger/fabric-ca:$CA_IMAGETAG fabric-ca-client version | sed -ne 's/ Version: //p' | head -1)
    echo "CA_LOCAL_VERSION=$CA_LOCAL_VERSION"
    echo "CA_DOCKER_IMAGE_VERSION=$CA_DOCKER_IMAGE_VERSION"

    if [ "$CA_LOCAL_VERSION" != "$CA_DOCKER_IMAGE_VERSION" ]; then
      echo "=================== WARNING ======================"
      echo "  Local fabric-ca binaries and docker images are  "
      echo "  out of sync. This may cause problems.           "
      echo "=================================================="
    fi
  fi
}

function generateIdentityForOrganization() {
  local org=$1
  echo ">>> create $org identity"
  set -x
  cryptogen generate --config=./organizations/crypto-config-"${org}".yaml --output="fixtures/organizations"
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo $'\e[1;32m'"Failed to generate certificates..."$'\e[0m'
    exit 1
  fi
}

function generateChannelConfigurationTransaction() {
  local profile=$1
  local channel=$2
  shift 2

  echo ">>> Generating channel configuration transaction '${channel}.tx'"
  set -x
  configtxgen -profile "${profile}" -outputCreateChannelTx ./channel-artifacts/"${channel}".tx -channelID "${channel}"
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Failed to generate channel configuration transaction..."
    exit 1
  fi
}

function generateAnchorPeerUpdate() {
  local profile=$1
  local channel=$2
  shift 2

  for msp in "$@"; do
    echo ">>> generating anchor peer update for ${msp}"
    set -x
    configtxgen -profile "${profile}" -outputAnchorPeersUpdate ./fixtures/channel-artifacts/${msp}-anchor-"${channel}".tx -channelID "${channel}" -asOrg ${msp}
    res=$?
    set +x
    if [ $res -ne 0 ]; then
      echo "Failed to generate anchor peer update for ${msp}..."
      exit 1
    fi
  done
}

function networkUp() {
  if [ -d "fixtures/organizations/peerOrganizations" ]; then
    rm -Rf fixtures/organizations/peerOrganizations && rm -Rf fixtures/organizations/ordererOrganizations
  fi

  generateIdentityForOrganization orderer
  generateIdentityForOrganization auditor

  configtxgen -profile Genesis -channelID system-channel -outputBlock fixtures/channel-artifacts/genesis.block
  configtxgen -profile Global -outputCreateChannelTx ./fixtures/channel-artifacts/global.tx -channelID global

  generateAnchorPeerUpdate Global global auditor

  COMPOSE_FILES="-f ${COMPOSE_FILE_BASE}"

  if [ "${DATABASE}" == "couchdb" ]; then
    COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"
  fi

  IMAGE_TAG=$IMAGETAG docker-compose ${COMPOSE_FILES} up --remove-orphans -d 2>&1

  docker ps -a
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start network"
    exit 1
  fi

  echo "Sleeping 10s to allow Raft cluster to complete booting"
  sleep 10

  docker exec cli.auditor.example.com scripts/script.sh $CLI_DELAY $CLI_TIMEOUT $VERBOSE
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Test failed"
    exit 1
  fi
}

# addOrg
# $ORGANIZATION - organization name
# For this organization need to create docker files here /docker/$ORGANIZATION/
function addOrg() {
  generateIdentityForOrganization "$ORGANIZATION"

  echo ">>> generating $ORGANIZATION organization definition"

  export FABRIC_CFG_PATH=$PWD/configtx/"$ORGANIZATION"
  configtxgen -printOrg "$ORGANIZATION" > ./fixtures/organizations/peerOrganizations/"$ORGANIZATION".example.com/"$ORGANIZATION".json

  IMAGE_TAG=${IMAGETAG} docker-compose -f docker/docker-compose-"$ORGANIZATION".yaml -f docker/docker-compose-couch-"$ORGANIZATION".yaml up -d 2>&1

  docker exec cli.orderer.example.com scripts/add-new-org-to-system-channel.sh "$ORGANIZATION" system-channel

  docker exec cli.$ORGANIZATION.example.com scripts/add-new-org-to-channel.sh "$ORGANIZATION" "$CHANNEL_NAME"

  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    echo "Error !!! adding $ORGANIZATION was failed"
    exit 1
  fi

}


# Tear down running network
function networkDown() {
  # stop org3 containers also in addition to org1 and org2, in case we were running sample to add org3
  docker-compose -f $COMPOSE_FILE_BASE -f $COMPOSE_FILE_COUCH down --volumes --remove-orphans
  docker-compose -f $COMPOSE_FILE_ORG1 -f $COMPOSE_FILE_COUCH_ORG1 down --volumes --remove-orphans
  docker-compose -f $COMPOSE_FILE_ORG2 -f $COMPOSE_FILE_COUCH_ORG2 down --volumes --remove-orphans
  docker-compose -f $COMPOSE_FILE_ORG3 -f $COMPOSE_FILE_COUCH_ORG3 down --volumes --remove-orphans
#  docker-compose -f $COMPOSE_FILE_COUCH_VERIZON -f $COMPOSE_FILE_VERIZON down --volumes --remove-orphans
#  docker-compose -f docker/docker-compose-ent.yaml down --volumes --remove-orphans
  # Don't remove the generated artifacts -- note, the ledgers are always removed
#  if [ "$MODE" != "restart" ]; then
    # Bring down the network, deleting the volumes
    #Cleanup the chaincode containers
    clearContainers
    #Cleanup images
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf fixtures/channel-artifacts/*.block fixtures/channel-artifacts/*.tx fixtures/organizations/peerOrganizations fixtures/organizations/ordererOrganizations'
    ## remove fabric ca artifacts
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org1/msp organizations/fabric-ca/org1/tls-cert.pem organizations/fabric-ca/org1/ca-cert.pem organizations/fabric-ca/org1/IssuerPublicKey organizations/fabric-ca/org1/IssuerRevocationPublicKey organizations/fabric-ca/org1/fabric-ca-server.db'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/org2/msp organizations/fabric-ca/org2/tls-cert.pem organizations/fabric-ca/org2/ca-cert.pem organizations/fabric-ca/org2/IssuerPublicKey organizations/fabric-ca/org2/IssuerRevocationPublicKey organizations/fabric-ca/org2/fabric-ca-server.db'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf organizations/fabric-ca/ordererOrg/msp organizations/fabric-ca/ordererOrg/tls-cert.pem organizations/fabric-ca/ordererOrg/ca-cert.pem organizations/fabric-ca/ordererOrg/IssuerPublicKey organizations/fabric-ca/ordererOrg/IssuerRevocationPublicKey organizations/fabric-ca/ordererOrg/fabric-ca-server.db'
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf addOrg3/fabric-ca/org3/IssuerRevocationPublicKey addOrg3/fabric-ca/org3/fabric-ca-server.db'
    # remove channel and script artifacts
    docker run --rm -v $(pwd):/data busybox sh -c 'cd /data && rm -rf channel-artifacts log.txt fabcar.tar.gz fabcar'
#
#  fi
}

# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# Using crpto vs CA. default is cryptogen
CRYPTO="cryptogen"
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
MAX_RETRY=5
# default for delay between commands
CLI_DELAY=2
# channel name defaults to "mychannel"
CHANNEL_NAME="global"
# chaincode name defaults to "basic"
CC_NAME="basic"
# chaincode path defaults to "NA"
CC_SRC_PATH="NA"
# endorsement policy defaults to "NA". This would allow chaincodes to use the majority default policy.
CC_END_POLICY="NA"
# collection configuration defaults to "NA"
CC_COLL_CONFIG="NA"
# chaincode init function defaults to "NA"
CC_INIT_FCN="NA"
# organization init function defaults to "auditor"
ORGANIZATION="auditor"

# use this as the default docker-compose yaml definition
COMPOSE_FILE_BASE=docker/docker-compose.yaml
# docker-compose.yaml file if you are using couchdb
COMPOSE_FILE_COUCH=docker/docker-compose-couch.yaml
# certificate authorities compose file
COMPOSE_FILE_CA=docker/docker-compose-ca.yaml

# org1
COMPOSE_FILE_ORG1=docker/docker-compose-org1.yaml
COMPOSE_FILE_COUCH_ORG1=docker/docker-compose-couch-org1.yaml
COMPOSE_FILE_CA_ORG1=docker/docker-compose-ca-org1.yaml

# org2
COMPOSE_FILE_ORG2=docker/docker-compose-org2.yaml
COMPOSE_FILE_COUCH_ORG2=docker/docker-compose-couch-org2.yaml
COMPOSE_FILE_CA_ORG2=docker/docker-compose-ca-org2.yaml

# org3
COMPOSE_FILE_ORG3=docker/docker-compose-org3.yaml
COMPOSE_FILE_COUCH_ORG3=docker/docker-compose-couch-org3.yaml
COMPOSE_FILE_CA_ORG3=docker/docker-compose-ca-org3.yaml

# use go as the default language for chaincode
CC_SRC_LANGUAGE="go"
# Chaincode version
CC_VERSION="1.0"
# Chaincode definition sequence
CC_SEQUENCE=1
# default image tag
IMAGETAG="latest"
# default ca image tag
CA_IMAGETAG="latest"
# default database
DATABASE="leveldb"

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]] ; then
  printHelp
  exit 0
else
  MODE=$1
  shift
fi

# parse a add subcommand if used
if [[ $# -ge 1 ]] ; then
  key="$1"
  if [[ "$key" == "add" ]]; then
      export MODE="add"
      shift
  fi
fi

# parse flags

while [[ $# -ge 1 ]] ; do
  key="$1"
  case $key in
  -h )
    printHelp
    exit 0
    ;;
  -c )
    CHANNEL_NAME="$2"
    shift
    ;;
  -p )
    CONFIGTX_PROFILE="$2"
    shift
    ;;
  -o )
    ORGANIZATION="$2"
    shift
    ;;
  -ca )
    CRYPTO="Certificate Authorities"
    ;;
  -r )
    MAX_RETRY="$2"
    shift
    ;;
  -d )
    CLI_DELAY="$2"
    shift
    ;;
  -s )
    DATABASE="$2"
    shift
    ;;
  -ccl )
    CC_SRC_LANGUAGE="$2"
    shift
    ;;
  -ccn )
    CC_NAME="$2"
    shift
    ;;
  -ccv )
    CC_VERSION="$2"
    shift
    ;;
  -ccs )
    CC_SEQUENCE="$2"
    shift
    ;;
  -ccp )
    CC_SRC_PATH="$2"
    shift
    ;;
  -ccep )
    CC_END_POLICY="$2"
    shift
    ;;
  -cccg )
    CC_COLL_CONFIG="$2"
    shift
    ;;
  -cci )
    CC_INIT_FCN="$2"
    shift
    ;;
  -i )
    IMAGETAG="$2"
    shift
    ;;
  -cai )
    CA_IMAGETAG="$2"
    shift
    ;;
  -verbose )
    VERBOSE=true
    shift
    ;;
  * )
    echo
    echo "Unknown flag: $key"
    echo
    printHelp
    exit 1
    ;;
  esac
  shift
done

# Are we generating crypto material with this command?
if [ ! -d "organizations/peerOrganizations" ]; then
  CRYPTO_MODE="with crypto from '${CRYPTO}'"
else
  CRYPTO_MODE=""
fi

# Determine mode of operation and printing out what we asked for
if [ "$MODE" == "up" ]; then
  echo "Starting nodes with CLI timeout of '${MAX_RETRY}' tries and CLI delay of '${CLI_DELAY}' seconds and using database '${DATABASE}' ${CRYPTO_MODE}"
  echo
elif [ "$MODE" == "addOrg" ]; then
  echo ">>> adding new organization to the network..."
  echo
elif [ "$MODE" == "down" ]; then
  echo "Stopping network"
  echo
elif [ "$MODE" == "restart" ]; then
  echo "Restarting network"
  echo
else
  printHelp
  exit 1
fi

if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "addOrg" ]; then
  addOrg
elif [ "${MODE}" == "down" ]; then
  networkDown
elif [ "${MODE}" == "restart" ]; then
  networkDown
  networkUp
else
  printHelp
  exit 1
fi
