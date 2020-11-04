package main

import (
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type Registration struct {
	contractapi.Contract
}

func (r *Registration) Register(ctx contractapi.TransactionContextInterface, org string) error {
	t := time.Now().Format("2006-01-02T15:04:05.999Z")
	err := ctx.GetStub().PutState(org + "#" + t, []byte(t))
	if err != nil {
		return err
	}
	return nil
}

func main() {
	chaincode, err := contractapi.NewChaincode(new(Registration))

	if err != nil {
		fmt.Printf("Error create registration chaincode: %s", err.Error())
		return
	}

	if err := chaincode.Start(); err != nil {
		fmt.Printf("Error starting registration chaincode: %s", err.Error())
	}
}
