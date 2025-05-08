package main

import (
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func New(debug bool) (*zap.Logger, error) {
	var config zap.Config
	if debug {
		config = zap.NewDevelopmentConfig()
		config.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	} else {
		config = zap.NewProductionConfig()
	}
	config.EncoderConfig.StacktraceKey = ""
	config.EncoderConfig.TimeKey = ""

	if logger, err := config.Build(); nil != err {
		return nil, err
	} else {
		return logger, nil
	}
}

func NewDefault() (*zap.Logger, error) {
	return New(true)
}
