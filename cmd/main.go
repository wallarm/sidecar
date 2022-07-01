package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
)

var (
	infoLogger    *log.Logger
	warningLogger *log.Logger
	errorLogger   *log.Logger
)

var (
	port                                   int
	sidecarTemplateFile, sidecarValuesFile string
	tlsCertFile, tlsKeyFile                string
	webhookInjectPath, webhookHealthPath   string
)

func init() {
	// init loggers
	infoLogger = log.New(os.Stderr, "INFO: ", log.Ldate|log.Ltime|log.Lshortfile)
	warningLogger = log.New(os.Stderr, "WARNING: ", log.Ldate|log.Ltime|log.Lshortfile)
	errorLogger = log.New(os.Stderr, "ERROR: ", log.Ldate|log.Ltime|log.Lshortfile)
}

func main() {
	// init command flags
	flag.IntVar(&port, "port", 8443, "Webhook server port")
	flag.StringVar(&sidecarTemplateFile, "sidecar-template", "/etc/webhook/config/sidecar-template.yaml", "Sidecar injector GO template file")
	flag.StringVar(&sidecarValuesFile, "sidecar-config", "/etc/webhook/config/sidecar-config.yaml", "Sidecar injector config file")
	flag.StringVar(&tlsCertFile, "tls-cert", "/usr/local/certificates/cert", "x509 Certificate file")
	flag.StringVar(&tlsKeyFile, "tls-key", "/usr/local/certificates/key", "x509 private key file")
	flag.StringVar(&webhookInjectPath, "webhook-inject-path", "/inject", "Path to webhook injection endpoint")
	flag.StringVar(&webhookHealthPath, "webhook-health-path", "/healthz", "Path of webhook health check endpoint")
	flag.Parse()

	tlsConfig, err := loadTlsConfig(tlsCertFile, tlsKeyFile)
	if err != nil {
		errorLogger.Fatalf("Failed to TLS config: %v", err)
	}

	sidecarDefaults, err := loadSidecarDefaults(sidecarValuesFile)
	if err != nil {
		errorLogger.Fatalf("Failed to load sidecar values file: %v", err)
	}

	sidecarTemplate, err := loadSidecarTemplate(sidecarTemplateFile)
	if err != nil {
		errorLogger.Fatalf("Failed to load sidecar template file: %v", err)
	}

	whsvr := &WebhookServer{
		sidecarTemplate: sidecarTemplate,
		sidecarDefaults: sidecarDefaults,
		server: &http.Server{
			Addr:      fmt.Sprintf(":%v", port),
			TLSConfig: tlsConfig,
		},
	}

	// define http server and server handler
	mux := http.NewServeMux()
	mux.HandleFunc(webhookInjectPath, whsvr.serve)
	mux.HandleFunc(webhookHealthPath, whsvr.serveHealth)
	whsvr.server.Handler = mux

	// start webhook server in new rountine
	go func() {
		if err := whsvr.server.ListenAndServeTLS("", ""); err != nil {
			errorLogger.Fatalf("Failed to listen and serve webhook server: %v", err)
		}
	}()

	// listening OS shutdown singal
	signalChan := make(chan os.Signal, 1)
	signal.Notify(signalChan, syscall.SIGINT, syscall.SIGTERM)
	<-signalChan

	infoLogger.Printf("Got OS shutdown signal, shutting down webhook server gracefully...")
	whsvr.server.Shutdown(context.Background())
}
