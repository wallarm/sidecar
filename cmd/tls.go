package main

import (
	"crypto/tls"
	"io/ioutil"
)

func loadFile(path string) ([]byte, error) {
	raw, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return raw, nil
}

func loadTlsConfig(certPath string, keyPath string) (*tls.Config, error) {
	cert, err := loadFile(certPath)
	if err != nil {
		return nil, err
	}
	key, err := loadFile(keyPath)
	if err != nil {
		return nil, err
	}
	keyPair, err := tls.X509KeyPair(cert, key)
	if err != nil {
		return nil, err
	}

	return &tls.Config{Certificates: []tls.Certificate{keyPair}}, nil
}
