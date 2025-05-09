package main

func EmptyOrNilString(s *string) bool {
	return s == nil || *s == ""
}
