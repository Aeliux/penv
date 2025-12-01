package logger

import (
	"os"
	"path/filepath"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/natefinch/lumberjack.v2"
)

// Package-level logger you can import: logger.L() or logger.S()
var (
	zapLogger *zap.Logger
	S         *zap.SugaredLogger
)

// Init initializes the file logger (plain text) with rotation.
// logPath: file path (e.g., "logs/app.log")
// level: zapcore.DebugLevel, InfoLevel, ...
func Init(logPath string, level zapcore.Level) error {
	// ensure log dir exists
	if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
		return err
	}

	// lumberjack writer for rotation
	lumber := &lumberjack.Logger{
		Filename:   logPath,
		MaxSize:    100,  // MB
		MaxBackups: 7,    // keep last 7 files
		MaxAge:     30,   // days
		Compress:   true, // compress rotated files
	}

	// File encoder config: console encoder produces readable text
	fileEncCfg := zap.NewProductionEncoderConfig()
	fileEncCfg.TimeKey = "ts"
	fileEncCfg.EncodeTime = zapcore.ISO8601TimeEncoder
	// Use non-color level encoder for files (CapitalLevelEncoder)
	fileEncCfg.EncodeLevel = zapcore.CapitalLevelEncoder
	// Show caller file:line
	fileEncCfg.EncodeCaller = zapcore.ShortCallerEncoder

	fileEncoder := zapcore.NewConsoleEncoder(fileEncCfg)

	// write syncer for file only
	fileWS := zapcore.AddSync(lumber)

	// Level enabler
	levelEnabler := zap.LevelEnablerFunc(func(lvl zapcore.Level) bool { return lvl >= level })

	// Core writing only to file (no stdout)
	core := zapcore.NewCore(fileEncoder, fileWS, levelEnabler)

	// add caller info and stacktrace on error
	logger := zap.New(core, zap.AddCaller(), zap.AddStacktrace(zapcore.ErrorLevel))

	// Replace global
	zapLogger = logger
	S = logger.Sugar()

	// Record initial startup message
	S.Infof("logger initialized; file=%s level=%s", logPath, level.String())
	return nil
}

// L returns the raw zap.Logger (may be nil if Init not called)
func L() *zap.Logger {
	return zapLogger
}
