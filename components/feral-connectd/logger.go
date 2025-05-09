package main

import (
	"os"

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

	// Enable caller information
	config.EncoderConfig.CallerKey = "caller"
	config.EncoderConfig.EncodeCaller = zapcore.ShortCallerEncoder

	logFile, err := os.OpenFile("/home/feralfile/.logs/connectd.txt", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return nil, err
	}

	// Create console encoder with colors
	consoleEncoder := zapcore.NewConsoleEncoder(config.EncoderConfig)

	// Create file encoder without colors
	fileEncoderConfig := config.EncoderConfig
	fileEncoderConfig.EncodeLevel = zapcore.CapitalLevelEncoder // No colors for file output
	fileEncoder := zapcore.NewConsoleEncoder(fileEncoderConfig)

	// Create core with both console and file outputs
	core := zapcore.NewTee(
		zapcore.NewCore(consoleEncoder, zapcore.AddSync(os.Stdout), config.Level),
		zapcore.NewCore(fileEncoder, zapcore.AddSync(logFile), config.Level),
	)

	// Create the logger with the custom core
	logger := zap.New(core, zap.AddCaller())
	return logger, nil
}

func NewDefault() (*zap.Logger, error) {
	return New(true)
}
