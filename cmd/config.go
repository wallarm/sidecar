package main

import (
	"crypto/tls"
	"errors"
	"fmt"
	"os"
	"strings"
	"text/template"

	"github.com/alexflint/go-arg"
	"github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"sigs.k8s.io/yaml"
)

const tokenEnvVar = "WALLARM_API_TOKEN"

var config Config

type Config struct {
	Controller struct {
		Listen string
	} `yaml:"-" json:"-"`
	TLSConfig    tls.Config         `yaml:"-" json:"-"`
	Deserializer runtime.Decoder    `yaml:"-" json:"-"`
	Template     *template.Template `yaml:"-" json:"-"`
	Settings     TemplateContext    `yaml:"settings"`
	Secrets      Secrets            `yaml:"-" json:"-"`
}

type Secrets struct {
	Token string
}

type Args struct {
	Listen      string `arg:"-l,--listen" env:"LISTEN" default:":8443" help:"listen address"`
	Template    string `arg:"--template" env:"TEMPLATE_FILE" default:"/etc/controller/template.yaml.tpl" help:"template file with patch for webhooks"`
	TLSCertFile string `arg:"--tls-cert-file" env:"TLS_CERT_FILE" default:"/etc/controller/tls/tls.crt" help:"certificate file for listen server"`
	TLSKeyFile  string `arg:"--tls-key-file" env:"TLS_KEY_FILE" default:"/etc/controller/tls/tls.key" help:"certificate key file for listen server"`
	ConfigFile  string `arg:"-c,--config" env:"CONFIG" default:"/etc/controller/config.yaml" help:"config location"`
	LogLevel    string `arg:"--log-level" env:"LOG_LEVEL" default:"info" help:"verbosity level, only \"error\", \"warn\", \"info\", \"debug\" are valid"`
	LogFormat   string `arg:"--log-format" env:"LOG_FORMAT" default:"text" help:"log format, only \"text\", \"text-color\", \"json\" are valid"`
}

func (c *Config) InitLogging(level, format string) error {
	foundErrors := make([]error, 0)

	logrus.SetOutput(os.Stdout)

	switch strings.ToLower(level) {
	case "error":
		logrus.SetLevel(logrus.ErrorLevel)
	case "warn":
		logrus.SetLevel(logrus.WarnLevel)
	case "info":
		logrus.SetLevel(logrus.InfoLevel)
	case "debug":
		logrus.SetLevel(logrus.DebugLevel)
	case "trace":
		logrus.SetLevel(logrus.TraceLevel)
	default:
		foundErrors = append(foundErrors, fmt.Errorf("Failed to initialize logging: bad log level \"%s\". Use one of these: \"error\", \"warn\", \"info\" (default), \"debug\".", level))
	}

	switch strings.ToLower(format) {
	case "text":
		logrus.SetFormatter(&logrus.TextFormatter{
			ForceColors: true,
		})
	case "text-color":
		logrus.SetFormatter(&logrus.TextFormatter{
			FullTimestamp: true,
			ForceColors:   true,
		})
	case "json":
		logrus.SetFormatter(&logrus.JSONFormatter{})
	default:
		foundErrors = append(foundErrors, fmt.Errorf("Failed to initialize logging: bad log format \"%s\". Use one of these: \"text\" (default), \"text-color\", \"json\".", format))
	}

	if len(foundErrors) > 0 {
		for _, v := range foundErrors {
			logrus.WithFields(logrus.Fields{
				"action": "loggerinit",
			}).Error(v.Error())
		}
		return fmt.Errorf("Failed to init logging: found %d errors, see output above", len(foundErrors))
	}

	logrus.WithFields(logrus.Fields{
		"action": "loggerinit",
	}).Debugf("Logging stream successfully initialized")

	return nil
}

func (c *Config) InitConfig(filename string) error {
	isThereError := false

	// Read file
	configFileContent, errFileContent := os.ReadFile(filename)
	if errFileContent != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Failed during reading configuration: %s", errFileContent.Error())
		isThereError = true
	}
	errConfigUnmarshal := yaml.Unmarshal([]byte(configFileContent), c)
	if errConfigUnmarshal != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Failed during reading configuration: %s", errConfigUnmarshal.Error())
		isThereError = true
	}

	// TODO Set defaults

	// TODO Validate values

	if isThereError {
		return errors.New("Found errors during config file initialization. Please see output above")
	}

	logrus.WithFields(logrus.Fields{
		"action": "config",
	}).Debug("Config file successfully initialized")

	return nil
}

func (c *Config) InitSecrets() error {
	isThereError := false

	token, ok := os.LookupEnv(tokenEnvVar)
	if !ok {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Evironment variable must be set: %s", tokenEnvVar)
		isThereError = true
	}

	if token == "" {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Evironment variable must not be empty: %s", tokenEnvVar)
		isThereError = true
	}

	c.Secrets.Token = token

	if isThereError {
		return errors.New("Found errors during initialization of environment variables. Please see output above")
	}

	logrus.WithFields(logrus.Fields{
		"action": "config",
	}).Debugf("Environment variables successfully initialized")

	return nil
}

func (c *Config) InitTLS(certfile, keyfile string) error {
	isThereError := false

	cert, errReadCertFile := os.ReadFile(certfile)
	if errReadCertFile != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Failed to read \"%s\": %s", certfile, errReadCertFile.Error())
		isThereError = true
	}

	key, errReadKeyFile := os.ReadFile(keyfile)
	if errReadKeyFile != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Failed to read \"%s\": %s", keyfile, errReadKeyFile.Error())
		isThereError = true
	}

	keypair, errX509KeyPair := tls.X509KeyPair(cert, key)
	if errX509KeyPair != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Failed to load key pair: %s", errX509KeyPair.Error())
		isThereError = true
	}

	c.TLSConfig = tls.Config{
		Certificates: []tls.Certificate{keypair},
	}

	if isThereError {
		return errors.New("Found errors during TLS config initialization. Please see output above")
	}

	logrus.WithFields(logrus.Fields{
		"action": "config",
	}).Debug("TLS configuration successfully initialized")

	return nil
}

func (c *Config) InitTemplate(templatefile string) error {
	isThereError := false

	content, errReadFile := os.ReadFile(templatefile)
	if errReadFile != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Failed to read \"%s\": %s", templatefile, errReadFile.Error())
		isThereError = true
	}

	tmplfuncs := template.FuncMap{
		"getAnnotation":        GetAnnotation,
		"getAppPort":           GetAppPort,
		"fromJson":             FromJson,
		"fromYaml":             FromYaml,
		"indent":               Indent,
		"isSet":                IsSet,
		"nindent":              Nindent,
		"toBool":               ToBool,
		"toJson":               ToJson,
		"toYaml":               ToYaml,
		"b64enc":               B64enc,
		"b64dec":               B64dec,
		"withAnnotationPrefix": WithAnnotationPrefix,
		"withAP":               WithAnnotationPrefix,
	}

	tmpl, errNewTemplate := template.New("basic").Funcs(tmplfuncs).Parse(string(content))
	if errNewTemplate != nil {
		logrus.WithFields(logrus.Fields{
			"action": "config",
		}).Errorf("Unable to parse template \"%s\": %s", templatefile, errNewTemplate.Error())
		isThereError = true
	}

	c.Template = tmpl

	if isThereError {
		return errors.New("Found errors during template initialization. Please see output above")
	}

	logrus.WithFields(logrus.Fields{
		"action": "config",
	}).Debug("Template successfully initialized")

	return nil
}

func (c *Config) Init() error {
	isThereError := false

	var args Args

	arg.MustParse(&args)

	if err := c.InitLogging(args.LogLevel, args.LogFormat); err != nil {
		return err
	}

	if err := c.InitConfig(args.ConfigFile); err != nil {
		return err
	}

	if err := c.InitSecrets(); err != nil {
		return err
	}

	if err := c.InitTLS(args.TLSCertFile, args.TLSKeyFile); err != nil {
		return err
	}

	if err := c.InitTemplate(args.Template); err != nil {
		return err
	}

	c.Deserializer = serializer.NewCodecFactory(runtime.NewScheme()).UniversalDeserializer()

	// Controller-specific settings
	c.Controller.Listen = args.Listen

	logrus.WithFields(logrus.Fields{
		"action":   "config",
		"variable": "config",
		"value":    ToJson(config),
	}).Trace()

	if isThereError {
		return errors.New("Found error during initialization. Please see output above")
	}

	return nil
}
