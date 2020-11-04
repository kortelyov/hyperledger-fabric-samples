* install golang from https://golang.org/dl/
* install / download hyperledger binaries

<code>
cd $GOPATH/src/github.com/hyperledger
</code>
<p></p>
<code>
curl -sSL https://bit.ly/2ysbOFE | bash -s
</code>

<p></p>

additional information: https://hyperledger-fabric.readthedocs.io/en/release-2.2/install.html

* copy binaries from fabric-samples/bin to your PATH

* clone github.com/kortelyov/hyperledger-fabric-samples

<code>
./network.sh up -s couchdb
</code>
<p></p>
<code>
./network.sh addOrg -o org1 -c global
</code>