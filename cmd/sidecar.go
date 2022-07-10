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
	Config     *TemplateContext
	ObjectMeta *metav1.ObjectMeta
	PodSpec    *corev1.PodSpec
}

func ConstructSidecar(tmpl *template.Template, sctx SidecarContext) (*Sidecar, error) {
	tmplresult := bytes.NewBuffer(make([]byte, 0))

	// TODO: Repack template file to remove Global
	ttt := struct {
		Config *struct {
			Global TemplateContext `yaml:"config"`
		}
		ObjectMeta *metav1.ObjectMeta
		PodSpec    *corev1.PodSpec
	}{
		Config: &struct {
			Global TemplateContext `yaml:"config"`
		}{
			Global: *sctx.Config,
		},
		ObjectMeta: sctx.ObjectMeta,
		PodSpec:    sctx.PodSpec,
	}

	logrus.WithFields(logrus.Fields{
		"action":      "constructsidecar",
		"variable":    "sctx",
		"description": "template function data (input)",
		// "value":       ToJson(sctx),
		"value": ToJson(ttt),
	}).Trace()

	// if errExecute := tmpl.Execute(tmplresult, sctx); errExecute != nil {
	if errExecute := tmpl.Execute(tmplresult, ttt); errExecute != nil {
		return nil, fmt.Errorf("Failed to render template: %s", errExecute.Error())
	}

	logrus.WithFields(logrus.Fields{
		"action":      "constructsidecar",
		"variable":    "tmplresult",
		"description": "template function returns",
		"value":       tmplresult.String(),
	}).Trace()

	logrus.WithFields(logrus.Fields{
		"action": "constructsidecar",
	}).Debug("Successfully render sidecar template")

	var sidecar Sidecar

	if errUnmarshal := yaml.Unmarshal(tmplresult.Bytes(), &sidecar); errUnmarshal != nil {
		return nil, fmt.Errorf("Failed to constuct sidecar patch: %s", errUnmarshal.Error())
	}

	logrus.WithFields(logrus.Fields{
		"action": "constructsidecar",
	}).Debug("Successfully constructred sidecar patch")

	return &sidecar, nil
}
