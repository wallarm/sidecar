package main

import (
	"bytes"
	"fmt"
	"text/template"

	"github.com/sirupsen/logrus"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/yaml"
)

type Sidecar struct {
	InitContainers []corev1.Container `yaml:"initContainers"`
	Containers     []corev1.Container `yaml:"containers"`
	Volumes        []corev1.Volume    `yaml:"volumes"`
}

type TemplateContext map[string]interface{}

type SidecarContext struct {
	Profile    *TemplateContext
	Config     *TemplateContext
	ObjectMeta *metav1.ObjectMeta
	PodSpec    *corev1.PodSpec
	Secrets    *Secrets
}

func ConstructSidecar(tmpl *template.Template, sctx SidecarContext) (*Sidecar, error) {
	tmplResult := bytes.NewBuffer(make([]byte, 0))

	logrus.WithFields(logrus.Fields{
		"action":      "constructsidecar",
		"variable":    "sctx",
		"description": "template function data (input)",
		"value":       ToJson(sctx),
	}).Trace()

	if errExecute := tmpl.Execute(tmplResult, sctx); errExecute != nil {
		return nil, fmt.Errorf("Failed to render template: %s", errExecute.Error())
	}

	fmt.Printf("%+v\n", tmplResult)
	logrus.WithFields(logrus.Fields{
		"action":      "constructsidecar",
		"variable":    "tmplResult",
		"description": "template function returns",
		"value":       tmplResult.String(),
	}).Trace()

	logrus.WithFields(logrus.Fields{
		"action": "constructsidecar",
	}).Debug("Successfully rendered sidecar template")

	var sidecar Sidecar

	if errUnmarshal := yaml.Unmarshal(tmplResult.Bytes(), &sidecar); errUnmarshal != nil {
		return nil, fmt.Errorf("Failed to constuct sidecar patch: %s", errUnmarshal.Error())
	}

	logrus.WithFields(logrus.Fields{
		"action": "constructsidecar",
	}).Debug("Successfully constructred sidecar patch")

	return &sidecar, nil
}
