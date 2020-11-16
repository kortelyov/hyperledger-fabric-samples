package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"sort"
	"strings"

	"github.com/astaxie/flatmap"
)

const ApplicationGroup = "channel_group.groups.Application.groups"
const MspIdentifier = "principal.msp_identifier"
const AdminPolicy = "Admins.policy"

func main() {

	file, err := os.Open("/opt/gopath/src/github.com/hyperledger/fabric/peer/config.json")
	if err != nil {
		fmt.Println(err)
	}
	defer file.Close()

	b, err := ioutil.ReadAll(file)
	if err != nil {
		fmt.Println(err)
	}

	var mp map[string]interface{}
	if err := json.Unmarshal(b, &mp); err != nil {
		log.Fatal(err)
	}
	fm, err := flatmap.Flatten(mp)
	if err != nil {
		log.Fatal(err)
	}
	var ks []string
	for k := range fm {
		ks = append(ks, k)
	}
	sort.Strings(ks)

	var env string
	for _, k := range ks {
		if strings.Contains(k, ApplicationGroup) &&
			strings.Contains(k, MspIdentifier) &&
			strings.Contains(k, AdminPolicy) {
			env += fm[k] + "\n"
		}
	}

	err = ioutil.WriteFile("/opt/gopath/src/github.com/hyperledger/fabric/peer/channel_orgs.txt", []byte(env), 0644)
	if err != nil {
		fmt.Println(err)
	}

}
