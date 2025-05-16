package main

import (
	"os"

	"github.com/natefinch/lumberjack"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

const (
	LOG_FILE       = "/home/feralfile/.logs/profilerd.log"
	DEBUG_LOG_FILE = "./profilerd.log"
)

func New(debug bool) (*zap.Logger, error) {
	var config zap.Config
	fp := LOG_FILE
	if debug {
		config = zap.NewDevelopmentConfig()
		config.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
		fp = DEBUG_LOG_FILE
	} else {
		config = zap.NewProductionConfig()
	}
	config.EncoderConfig.StacktraceKey = ""
	config.EncoderConfig.TimeKey = ""

	// Enable caller information
	config.EncoderConfig.CallerKey = "caller"
	config.EncoderConfig.EncodeCaller = zapcore.ShortCallerEncoder

	// Create console encoder with colors
	consoleEncoder := zapcore.NewConsoleEncoder(config.EncoderConfig)

	// Create file encoder without colors
	fileEncoderConfig := config.EncoderConfig
	fileEncoderConfig.EncodeLevel = zapcore.CapitalLevelEncoder // No colors for file output
	fileEncoder := zapcore.NewConsoleEncoder(fileEncoderConfig)

	// Set up lumberjack for log rotation
	logRotator := &lumberjack.Logger{
		Filename:   fp,
		MaxSize:    32,   // megabytes
		MaxBackups: 3,    // number of backups to keep
		MaxAge:     30,   // days to keep backups
		Compress:   true, // compress backups
	}

	// Create core with both console and file outputs
	core := zapcore.NewTee(
		zapcore.NewCore(consoleEncoder, zapcore.AddSync(os.Stdout), config.Level),
		zapcore.NewCore(fileEncoder, zapcore.AddSync(logRotator), config.Level),
	)

	// Create the logger with the custom core
	logger := zap.New(core, zap.AddCaller())
	return logger, nil
}

func NewDefault() (*zap.Logger, error) {
	return New(true)
}
