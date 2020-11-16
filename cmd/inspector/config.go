package main

type Config struct {
	ChannelGroup struct {
		Groups struct {
			Application struct {
				Groups struct {
					G string
				} `json:"groups"`
			} `json:"Application"`
		} `json:"groups"`
	} `json:"channel_group"`
}

//func (c *Config) UnmarshalJSON(b []byte) error {
//	fmt.Println("unmarshal")
//	g.M = make(map[string]interface{})
//	group := make(map[string]interface{})
//	err := json.Unmarshal(b, &group)
//	if err != nil {
//		return err
//	}
//	for key, value := range group {
//		//if key == "groups" {
//		//}
//		//g.M[key] = value
//		fmt.Println(key, value)
//		fmt.Println()
//	}
//	return nil
//}