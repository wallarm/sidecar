package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/yaml"

	"strings"
	"text/template"
)

type SidecarConfig struct {
	InitContainers []corev1.Container `yaml:"initContainers"`
	Containers     []corev1.Container `yaml:"containers"`
	Volumes        []corev1.Volume    `yaml:"volumes"`
}

type SidecarTemplateValues struct {
	Config     *TemplateDefaultValues
	ObjectMeta *metav1.ObjectMeta
	PodSpec    *corev1.PodSpec
}

type TemplateDefaultValues struct {
	Global  map[string]interface{} `yaml:"config"`
}

func fromJson(jsonString string) interface{} {
	var parsedJson interface{}
	err := json.Unmarshal([]byte(jsonString), &parsedJson)
	if err != nil {
		warningLogger.Printf("Unable to unmarshal %s", jsonString)
		return "{}"
	}
	return parsedJson
}

func getAnnotation(meta metav1.ObjectMeta, property string, defaultValue interface{}) string {
	value, ok := meta.Annotations[property]
	if !ok {
		value = fmt.Sprint(defaultValue)
	}
	return value
}

func getAppPort(podSpec corev1.PodSpec, defaultValue float64) int32 {
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
// 	defaultValueInt, err := strconv.Atoi(defaultValue)
// 	if err != nil {
// 		errorLogger.Fatalf("Unable to convert string to integer %v", defaultValue)
// 		panic(err)
// 	}
	return int32(defaultValue)
}

func toBool(value string) bool {
	switch value {
	case "true", "TRUE", "True":
		return true
	case "false", "FALSE", "False":
		return false
	}
	warningLogger.Printf("Unable to convert to boolean %v", value)
	return false
}

func toYaml(value interface{}) string {
	y, err := yaml.Marshal(value)
	if err != nil {
		warningLogger.Printf("Unable to marshal %v", value)
		return ""
	}
	return string(y)
}

func indent(spaces int, source string) string {
	res := strings.Split(source, "\n")
	for i, line := range res {
		if i > 0 {
			res[i] = fmt.Sprintf(fmt.Sprintf("%% %ds%%s", spaces), "", line)
		}
	}
	return strings.Join(res, "\n")
}

func isSet(m map[string]string, key string) bool {
	_, ok := m[key]
	return ok
}

func createTemplateExtraFuncs() template.FuncMap {
	return template.FuncMap{
		"getAnnotation": getAnnotation,
		"getAppPort":    getAppPort,
		"fromJson":      fromJson,
		"isSet":         isSet,
		"toBool":        toBool,
		"toYaml":        toYaml,
		"indent":        indent,
	}
}

func loadSidecarDefaults(filePath string) (*TemplateDefaultValues, error) {
	defaultValuesFile, err := ioutil.ReadFile(filePath)
	if err != nil {
		errorLogger.Fatalf("Unable to load config file:  %v", filePath)
		return nil, err
	}
	infoLogger.Printf("Successfully load config file:  %v", filePath)

	var defaultValues TemplateDefaultValues
	err = yaml.Unmarshal(defaultValuesFile, &defaultValues)
	if err != nil {
		errorLogger.Fatalf("Unable to unmarshal YAML from file:  %v", filePath)
		return nil, err
	}
	infoLogger.Printf("Successfully unmarshalled YAML from file: %v", filePath)
	return &defaultValues, nil
}

func loadSidecarTemplate(filePath string) (*template.Template, error) {
	buf, err := ioutil.ReadFile(filePath)
	if err != nil {
		errorLogger.Fatalf("Unable to load template file:  %v", filePath)
		return nil, err
	}
	infoLogger.Printf("Successfully loaded template file: %v", filePath)

	tmplExtraFuncs := createTemplateExtraFuncs()
	tmpl, err := template.New("").Funcs(tmplExtraFuncs).Parse(string(buf))
	if err != nil {
		errorLogger.Fatalf("Unable to parse template file: %v", filePath)
		return nil, err
	}
	infoLogger.Printf("Successfully parsed template file: %v", filePath)
	return tmpl, nil
}

func parseSidecarConfig(configFile []byte) (*SidecarConfig, error) {
	var cfg SidecarConfig
	err := yaml.Unmarshal(configFile, &cfg)
	if err != nil {
		errorLogger.Fatalf("Unable to parse sidecar config: %v", err)
		return nil, err
	}
	infoLogger.Printf("Successfully parsed sidecar config")
	return &cfg, nil
}

func renderSidecarTemplate(sidecarTemplate *template.Template, sidecarValues SidecarTemplateValues) (*SidecarConfig, error) {
	var buf strings.Builder
	err := sidecarTemplate.Execute(&buf, sidecarValues)
	if err != nil {
		errorLogger.Fatalf("Unable to render template: %v", err)
		return nil, err
	}
	infoLogger.Printf("Successfully rendered template")
	fmt.Printf("%+v\n", buf.String())

	sidecarConfig, err := parseSidecarConfig([]byte(buf.String()))
	if err != nil {
		return nil, err
	}
	return sidecarConfig, nil
}
