package logger

import (
	"os"
	"path/filepath"
	"sync"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/natefinch/lumberjack.v2"
)

// Config holds logger configuration options.
type Config struct {
	LogPath       string
	Level         zapcore.Level
	MaxSize       int           // MB
	MaxBackups    int           // number of old log files to keep
	MaxAge        int           // days
	Compress      bool          // compress rotated files
	AddCaller     bool          // include file:line caller info
	AddStacktrace zapcore.Level // add stacktrace at this level and above
	Development   bool          // enable development mode
	UseJSON       bool          // use JSON encoding instead of console
}

// DefaultConfig returns a sensible default configuration.
func DefaultConfig(logPath string) *Config {
	return &Config{
		LogPath:       logPath,
		Level:         zapcore.InfoLevel,
		MaxSize:       100,
		MaxBackups:    7,
		MaxAge:        30,
		Compress:      true,
		AddCaller:     true,
		AddStacktrace: zapcore.ErrorLevel,
		Development:   false,
		UseJSON:       false,
	}
}

// Package-level logger you can import: logger.L() or logger.S()
var (
	zapLogger *zap.Logger
	S         *zap.SugaredLogger
	mu        sync.RWMutex
	config    *Config
)

// Init initializes the file logger with the provided configuration.
func Init(cfg *Config) error {
	if cfg == nil {
		cfg = DefaultConfig("logs/app.log")
	}

	mu.Lock()
	defer mu.Unlock()

	config = cfg

	if err := initLocked(cfg); err != nil {
		return err
	}

	// Record initial startup message
	S.Infof("logger initialized; file=%s level=%s", cfg.LogPath, cfg.Level.String())
	return nil
}

// InitSimple is a convenience function for simple initialization.
// For more control, create a Config and call Init.
func InitSimple(logPath string, level zapcore.Level) error {
	cfg := DefaultConfig(logPath)
	cfg.Level = level
	return Init(cfg)
}

// L returns the raw zap.Logger (may be nil if Init not called).
func L() *zap.Logger {
	mu.RLock()
	defer mu.RUnlock()
	return zapLogger
}

// Sugar returns the sugared logger (may be nil if Init not called).
func Sugar() *zap.SugaredLogger {
	mu.RLock()
	defer mu.RUnlock()
	return S
}

// SetLevel changes the log level at runtime.
// Returns error if logger hasn't been initialized.
func SetLevel(level zapcore.Level) error {
	mu.Lock()
	defer mu.Unlock()

	if config == nil {
		return os.ErrInvalid
	}

	config.Level = level

	// Re-initialize with new config
	return initLocked(config)
}

// GetLevel returns the current log level.
// Returns InfoLevel if logger hasn't been initialized.
func GetLevel() zapcore.Level {
	mu.RLock()
	defer mu.RUnlock()

	if config == nil {
		return zapcore.InfoLevel
	}
	return config.Level
}

// GetConfig returns a copy of the current configuration.
// Returns nil if logger hasn't been initialized.
func GetConfig() *Config {
	mu.RLock()
	defer mu.RUnlock()

	if config == nil {
		return nil
	}

	// Return a copy to prevent external modification
	cfgCopy := *config
	return &cfgCopy
}

// Sync flushes any buffered log entries.
// Should be called before application exit.
func Sync() error {
	mu.RLock()
	defer mu.RUnlock()

	if zapLogger != nil {
		return zapLogger.Sync()
	}
	return nil
}

// initLocked is the internal init function that assumes mu is already locked.
func initLocked(cfg *Config) error {
	// ensure log dir exists
	if err := os.MkdirAll(filepath.Dir(cfg.LogPath), 0o755); err != nil {
		return err
	}

	// lumberjack writer for rotation
	lumber := &lumberjack.Logger{
		Filename:   cfg.LogPath,
		MaxSize:    cfg.MaxSize,
		MaxBackups: cfg.MaxBackups,
		MaxAge:     cfg.MaxAge,
		Compress:   cfg.Compress,
	}

	// Encoder config
	var encCfg zapcore.EncoderConfig
	if cfg.Development {
		encCfg = zap.NewDevelopmentEncoderConfig()
	} else {
		encCfg = zap.NewProductionEncoderConfig()
	}

	encCfg.TimeKey = "ts"
	encCfg.EncodeTime = zapcore.ISO8601TimeEncoder
	encCfg.EncodeLevel = zapcore.CapitalLevelEncoder

	if cfg.AddCaller {
		encCfg.EncodeCaller = zapcore.ShortCallerEncoder
	}

	// Choose encoder
	var encoder zapcore.Encoder
	if cfg.UseJSON {
		encoder = zapcore.NewJSONEncoder(encCfg)
	} else {
		encoder = zapcore.NewConsoleEncoder(encCfg)
	}

	// write syncer for file only
	fileWS := zapcore.AddSync(lumber)

	// Level enabler
	levelEnabler := zap.LevelEnablerFunc(func(lvl zapcore.Level) bool {
		return lvl >= cfg.Level
	})

	// Core writing only to file (no stdout)
	core := zapcore.NewCore(encoder, fileWS, levelEnabler)

	// Build logger with options
	opts := []zap.Option{}
	if cfg.AddCaller {
		opts = append(opts, zap.AddCaller())
	}
	if cfg.AddStacktrace != zapcore.FatalLevel+1 {
		opts = append(opts, zap.AddStacktrace(cfg.AddStacktrace))
	}
	if cfg.Development {
		opts = append(opts, zap.Development())
	}

	logger := zap.New(core, opts...)

	// Replace global
	zapLogger = logger
	S = logger.Sugar()

	return nil
}
