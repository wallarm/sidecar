package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/sirupsen/logrus"
)

type Server struct {
	Listen        string
	TLSConfig     tls.Config
	Paths         ServerPaths
	Mux           *http.ServeMux
	Server        http.Server
	Context       context.Context
	ContextCancel context.CancelFunc
}

type ServerPaths struct {
	Inject      string
	Ping        string
	HealthCheck string
	Metrics     string
}

type LRData struct {
	status int
	size   int
}

type LRWriter struct {
	http.ResponseWriter
	rdata *LRData
}

func (r *LRWriter) Write(b []byte) (int, error) {
	size, err := r.ResponseWriter.Write(b)
	r.rdata.size += size
	return size, err
}

func (r *LRWriter) WriteHeader(statusCode int) {
	r.ResponseWriter.WriteHeader(statusCode)
	r.rdata.status = statusCode
}

func (s *Server) MiddlewareAccessLog(h http.Handler) http.Handler {
	loggingFn := func(rw http.ResponseWriter, req *http.Request) {
		start := time.Now()

		lrw := LRWriter{
			ResponseWriter: rw,
			rdata: &LRData{
				status: 0,
				size:   0,
			},
		}

		h.ServeHTTP(&lrw, req)

		duration := time.Since(start)

		logrus.WithFields(logrus.Fields{
			"action":   "accesslog",
			"uri":      req.RequestURI,
			"method":   req.Method,
			"status":   lrw.rdata.status,
			"duration": duration,
			"size":     lrw.rdata.size,
		}).Info()
	}
	return http.HandlerFunc(loggingFn)
}

func (s *Server) HealthCheck(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "OK")
}

func (s *Server) Ping(w http.ResponseWriter, r *http.Request) {
	time.Sleep(time.Second * 15)
	fmt.Fprint(w, "OK")
}

func (s *Server) Init() error {
	s.Context, s.ContextCancel = context.WithCancel(context.Background())

	mux := http.NewServeMux()

	mux.Handle(s.Paths.Inject, s.MiddlewareAccessLog(http.HandlerFunc(InjectHandlerFunc)))

	mux.HandleFunc(s.Paths.HealthCheck, s.HealthCheck)
	mux.HandleFunc(s.Paths.Ping, s.Ping)
	mux.Handle(s.Paths.Metrics, promhttp.Handler())

	s.Server = http.Server{
		Addr:      config.Controller.Listen,
		TLSConfig: &config.TLSConfig,
		Handler:   mux,
		BaseContext: func(l net.Listener) context.Context {
			return s.Context
		},
	}

	return nil
}

func (s *Server) Run() error {
	logrus.WithFields(logrus.Fields{
		"action": "server",
	}).Debug("Starting to listen webhooks")

	go func() {
		errListen := s.Server.ListenAndServeTLS("", "")
		if errors.Is(errListen, http.ErrServerClosed) {
			logrus.WithFields(logrus.Fields{
				"action": "server",
			}).Info("Server stops listening requests")
		} else if errListen != nil {
			logrus.WithFields(logrus.Fields{
				"action": "server",
			}).Infof("Failure during server running: %s", errListen.Error())
		}
		s.ContextCancel()
	}()

	logrus.WithFields(logrus.Fields{
		"action": "server",
	}).Debug("Setting up signals listener")

	signalchannel := make(chan os.Signal, 1)
	signal.Notify(signalchannel, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		select {
		case <-signalchannel:
			s.Shutdown()
		}
	}()

	logrus.WithFields(logrus.Fields{
		"action": "server",
	}).Debug("Server has been started")

	return nil
}

func (s *Server) Shutdown() error {
	s.Server.Shutdown(s.Context)

	return nil
}

func (s *Server) WaitForClose() error {
	select {
	case <-s.Context.Done():
		return nil
	}
}
