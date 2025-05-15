package main

import (
	"os"
	"path/filepath"

	"github.com/natefinch/lumberjack"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

const (
	// File paths for logs
	DEBUG_LOG_FILE_PATH = "./feral-watchdog.log"
	LOG_FILE_PATH       = "/home/feralfile/.logs/feral-watchdog.log"
)

// ensureLogDirectory creates the log directory if it doesn't exist
func ensureLogDirectory() error {
	dir := filepath.Dir(LOG_FILE_PATH)
	return os.MkdirAll(dir, 0755)
}

func newLogger(debug bool) (*zap.Logger, error) {
	var config zap.Config
	fp := LOG_FILE_PATH
	if debug {
		config = zap.NewDevelopmentConfig()
		config.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
		fp = DEBUG_LOG_FILE_PATH
	} else {
		config = zap.NewProductionConfig()
	}

	if err := ensureLogDirectory(); err != nil {
		return nil, err
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
