package main

import (
	"encoding/binary"
)

func StringToUint64Varint(length int) ([]byte, error) {
	buf := make([]byte, binary.MaxVarintLen64)
	n := binary.PutUvarint(buf, uint64(length))
	return buf[:n], nil
}
