package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v2"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func GetAnnotation(meta metav1.ObjectMeta, property string, defaultValue interface{}) string {
	value, ok := meta.Annotations[WithAnnotationPrefix(property)]
	if !ok {
		value = fmt.Sprint(defaultValue)
	}
	return value
}

func GetAppPort(podSpec corev1.PodSpec, defaultValue float64) int32 {
	for _, container := range podSpec.Containers {
		for _, port := range container.Ports {
			if port.Name == "http" {
				return port.ContainerPort
			}
		}
	}

	for _, container := range podSpec.Containers {
		for _, port := range container.Ports {
			return port.ContainerPort
		}
	}

	return int32(defaultValue)
}

func ToBool(value string) bool {
	switch strings.ToLower(value) {
	case "true":
		return true
	case "false":
		return false
	}

	logrus.WithFields(logrus.Fields{
		"action": "templatefunc",
		"func":   "toBool",
	}).Infof("Unable to convert to boolean %s", value)

	return false
}

func FromJson(str string) interface{} {
	var object interface{}

	if err := json.Unmarshal([]byte(str), &object); err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "templatefunc",
			"func":   "fromJson",
		}).Infof("Failed to unmarshal %s: %s", strconv.Quote(str), err.Error())
		return nil
	}

	return object
}

func ToJson(value interface{}) string {
	j, err := json.Marshal(value)

	if err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "templatefunc",
			"func":   "toJson",
		}).Infof("Failed to marshall structure %v: %s", value, err.Error())
		return ""
	}

	return string(j)
}

func FromYaml(str string) interface{} {
	var object interface{}

	if err := yaml.Unmarshal([]byte(str), &object); err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "templatefunc",
			"func":   "fromYaml",
		}).Infof("Failed to unmarshal %s: %s", strconv.Quote(str), err.Error())
		return nil
	}

	return object
}

func ToYaml(value interface{}) string {
	y, err := yaml.Marshal(value)

	if err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "templatefunc",
			"func":   "toYaml",
		}).Infof("Failed to marshall structure %v: %s", value, err.Error())
		return ""
	}

	return string(y)
}

func Indent(spaces int, source string) string {
	res := strings.Split(source, "\n")

	for i, line := range res {
		if i > 0 {
			res[i] = fmt.Sprintf(fmt.Sprintf("%% %ds%%s", spaces), "", line)
		}
	}

	return strings.Join(res, "\n")
}

func Nindent(spaces int, source string) string {
	return fmt.Sprintf("\n%s", Indent(spaces, source))
}

func IsSet(m map[string]string, key string) bool {
	_, ok := m[WithAnnotationPrefix(key)]
	return ok
}

func B64enc(input string) string {
	return base64.StdEncoding.EncodeToString([]byte(input))
}

func B64dec(input string) string {
	output, errDecode := base64.StdEncoding.DecodeString(input)
	if errDecode != nil {
		logrus.WithFields(logrus.Fields{
			"action": "templatefunc",
			"func":   "b64dec",
		}).Infof("Failed to decode \"%s\" from base64: %s", input, errDecode.Error())
		return ""
	}
	return string(output)
}

func WithAnnotationPrefix(suffix string) string {
    prefix := fmt.Sprintf("%v", config.Settings["annotationPrefix"])
    return prefix + "/" + suffix
}