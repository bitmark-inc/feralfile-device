package main

import "fmt"

func EmptyOrNilString(s *string) bool {
	return s == nil || *s == ""
}

func GetIndexID(blockchain, contract, tokenID string) string {
	switch blockchain {
	case "bitmark":
		return fmt.Sprintf("bmk--%s", tokenID)
	case "ethereum":
		return fmt.Sprintf("eth-%s-%s", contract, tokenID)
	case "tezos":
		return fmt.Sprintf("tez-%s-%s", contract, tokenID)
	}
	return ""
}
