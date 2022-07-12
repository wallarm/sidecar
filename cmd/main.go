package main

import (
	"github.com/sirupsen/logrus"
)

func main() {
	if err := config.Init(); err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "main",
		}).Fatal(err.Error())
	}

	server := Server{
		Listen:    config.Controller.Listen,
		TLSConfig: config.TLSConfig,
		Paths: ServerPaths{
			Inject:      "/inject",
			Ping:        "/ping",
			HealthCheck: "/healthz",
			Metrics:     "/metrics",
		},
	}

	if err := server.Init(); err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "main",
		}).Fatal(err.Error())
	}

	if err := server.Run(); err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "main",
		}).Fatal(err.Error())
	}

	server.WaitForClose()

	logrus.WithFields(logrus.Fields{
		"action": "main",
	}).Info("Gracefully done! Bye!")
}
