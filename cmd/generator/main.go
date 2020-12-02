package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"strconv"
	"text/template"
)

type C struct {
	Organization string
	Domain       string
	Port         int
	Couch        int
}

type O struct {
	Orgs []string `json:"orgs"`
}

func main() {
	var orgs O
	count := flag.Int("count", 1, "number of organizations")
	f := flag.Bool("file", false, "read from orgs.json")
	flag.Parse()

	if *f {
		file, err := os.Open("orgs.json")
		if err != nil {
			panic(err)
		}
		defer file.Close()
		b, _ := ioutil.ReadAll(file)
		err = json.Unmarshal(b, &orgs)
		if err != nil {
			panic(err)
		}
	}

	t1, err := template.ParseFiles("crypto-config.yaml")
	if err != nil {
		panic("crypto-config.yaml template didn't found")
	}
	t2, err := template.ParseFiles("configtx.yaml")
	if err != nil {
		panic("configtx.yaml template didn't found")
	}
	t3, err := template.ParseFiles("docker-compose.yaml")
	if err != nil {
		panic("docker-compose.yaml template didn't found")
	}
	t4, err := template.ParseFiles("docker-compose-couch.yaml")
	if err != nil {
		panic("docker-compose-couch.yaml template didn't found")
	}

	var j int
	if x := len(orgs.Orgs); x > 0 {
		j = x
	} else {
		j = *count
	}

	for i := 1; i <= j; i++ {
		var c C
		if len(orgs.Orgs) > 0 {
			c.Organization = orgs.Orgs[i-1]
		} else {
			c.Organization = generate(i)
			c.Domain = ".example"
		}
		f1, err := os.Create(fmt.Sprintf("../../organizations/crypto-config-%s.yaml", c.Organization))
		if err != nil {
			panic("cannot create file:" + err.Error())
		}
		defer f1.Close()

		err = t1.Execute(f1, c)
		if err != nil {
			panic(err)
		}

		err = os.Mkdir(fmt.Sprintf("../../configtx/%s", c.Organization), 0755)
		if err != nil {
			panic(err)
		}
		f2, err := os.Create(fmt.Sprintf("../../configtx/%s/configtx.yaml", c.Organization))
		if err != nil {
			panic("cannot create file:" + err.Error())
		}
		defer f2.Close()
		p := strconv.Itoa(i+7) + "051"
		couch := strconv.Itoa(i+3) + "984"
		c.Port, _ = strconv.Atoi(p)
		c.Couch, _ = strconv.Atoi(couch)
		err = t2.Execute(f2, c)
		if err != nil {
			panic(err)
		}

		f3, err := os.Create(fmt.Sprintf("../../docker/docker-compose-%s.yaml", c.Organization))
		if err != nil {
			panic("cannot create file:" + err.Error())
		}
		err = t3.Execute(f3, c)
		if err != nil {
			panic(err)
		}

		f4, err := os.Create(fmt.Sprintf("../../docker/docker-compose-couch-%s.yaml", c.Organization))
		if err != nil {
			panic("cannot create file:" + err.Error())
		}
		err = t4.Execute(f4, c)
		if err != nil {
			panic(err)
		}
	}

}

func generate(i int) string {
	return fmt.Sprintf("org%s", strconv.Itoa(i))
}
