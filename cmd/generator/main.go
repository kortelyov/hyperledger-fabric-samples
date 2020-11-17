package main

import (
	"flag"
	"fmt"
	"os"
	"strconv"
	"text/template"
)

type C struct {
	Organization string
	Port         int
	Couch        int
}

func main() {
	count := flag.Int("count", 1, "number of organizations")
	withDocker := flag.Bool("docker", false, "is docker-compose files needed")
	flag.Parse()

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

	for i := 1; i <= *count; i++ {
		name := generate(i)
		fmt.Println(name)
		c := C{
			Organization: name,
		}
		f1, err := os.Create(fmt.Sprintf("../../organizations/crypto-config-%s.yaml", name))
		if err != nil {
			panic("cannot create file:" + err.Error())
		}
		defer f1.Close()

		err = t1.Execute(f1, c)
		if err != nil {
			panic(err)
		}

		err = os.Mkdir(fmt.Sprintf("../../configtx/%s", name), 0755)
		if err != nil {
			panic(err)
		}
		f2, err := os.Create(fmt.Sprintf("../../configtx/%s/configtx.yaml", name))
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

		if *withDocker {
			f3, err := os.Create(fmt.Sprintf("../../docker/docker-compose-%s.yaml", name))
			if err != nil {
				panic("cannot create file:" + err.Error())
			}
			err = t3.Execute(f3, c)
			if err != nil {
				panic(err)
			}

			f4, err := os.Create(fmt.Sprintf("../../docker/docker-compose-couch-%s.yaml", name))
			if err != nil {
				panic("cannot create file:" + err.Error())
			}
			err = t4.Execute(f4, c)
			if err != nil {
				panic(err)
			}
		}
	}

}

func generate(i int) string {
	return fmt.Sprintf("org%s", strconv.Itoa(i))
}
