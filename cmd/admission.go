package main

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/sirupsen/logrus"
	admissionv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type PatchOperation struct {
	Op    string      `json:"op"`
	Path  string      `json:"path"`
	Value interface{} `json:"value,omitempty"`
}

func WhetherMutate(metadata *metav1.ObjectMeta) bool {
	annotations := metadata.GetAnnotations()
	if annotations == nil {
		annotations = make(map[string]string)
	}

	status := annotations[fmt.Sprintf("%v/status", config.Settings["annotationPrefix"])]

	if strings.ToLower(status) == "injected" {
		logrus.WithFields(logrus.Fields{
			"action": "whethermutate",
		}).Debugf("Pod %s/%s already mutated", metadata.Namespace, metadata.Name)
		return false
	} else {
		return true
	}
}

func AddContainer(target, added []corev1.Container, basePath string) (patch []PatchOperation) {
	first := len(target) == 0
	var value interface{}
	for _, add := range added {
		value = add
		path := basePath
		if first {
			first = false
			value = []corev1.Container{add}
		} else {
			path = path + "/-"
		}
		patch = append(patch, PatchOperation{
			Op:    "add",
			Path:  path,
			Value: value,
		})
	}
	return patch
}

func AddVolume(target, added []corev1.Volume, basePath string) (patch []PatchOperation) {
	first := len(target) == 0
	var value interface{}
	for _, add := range added {
		value = add
		path := basePath
		if first {
			first = false
			value = []corev1.Volume{add}
		} else {
			path = path + "/-"
		}
		patch = append(patch, PatchOperation{
			Op:    "add",
			Path:  path,
			Value: value,
		})
	}
	return patch
}

func UpdateAnnotation(target map[string]string, added map[string]string) (patch []PatchOperation) {
	var operation string
	for key, value := range added {
		if target == nil {
			target = map[string]string{}
			patch = append(patch, PatchOperation{
				Op:   "add",
				Path: "/metadata/annotations",
				Value: map[string]string{
					key: value,
				},
			})
		} else {
			operation = "add"
			if target[key] != "" {
				operation = "replace"
			}
			key = strings.ReplaceAll(key, "/", "~1")
			patch = append(patch, PatchOperation{
				Op:    operation,
				Path:  "/metadata/annotations/" + key,
				Value: value,
			})
		}
	}
	return patch
}

func CreateMutationPatch(pod *corev1.Pod, sidecar *Sidecar, annotations map[string]string) ([]byte, error) {
	patch := make([]PatchOperation, 0)
	patch = append(patch, AddContainer(pod.Spec.InitContainers, sidecar.InitContainers, "/spec/initContainers")...)
	patch = append(patch, AddContainer(pod.Spec.Containers, sidecar.Containers, "/spec/containers")...)
	patch = append(patch, AddVolume(pod.Spec.Volumes, sidecar.Volumes, "/spec/volumes")...)
	patch = append(patch, UpdateAnnotation(pod.Annotations, annotations)...)

	return json.Marshal(patch)
}

func Mutate(ar *admissionv1.AdmissionReview) *admissionv1.AdmissionResponse {
	req := ar.Request
	var pod corev1.Pod

	if err := json.Unmarshal(req.Object.Raw, &pod); err != nil {
		logrus.WithFields(logrus.Fields{
			"action": "mutationreview",
		}).Debugf("Could not unmarshal raw object: %s", err.Error())
		return &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	logrus.WithFields(logrus.Fields{
		"action":    "mutationreview",
		"kind":      fmt.Sprintf("%v", req.Kind),
		"namespace": req.Namespace,
		"pod":       req.Name,
		"uid":       fmt.Sprintf("%v", req.UID),
		"operation": fmt.Sprintf("%v", req.Operation),
		"userinfo":  fmt.Sprintf("%v", req.UserInfo),
	}).Info()

	if !WhetherMutate(&pod.ObjectMeta) {
		logrus.WithFields(logrus.Fields{
			"action": "mutationreview",
		}).Debug("Skipping mutation for this pod due to policy check")
		return &admissionv1.AdmissionResponse{
			Allowed: true,
		}
	}

	sidecar, errConstructSidecar := ConstructSidecar(config.Template, SidecarContext{
		Config:     &config.Settings,
		Secrets:    &config.Secrets,
		ObjectMeta: &pod.ObjectMeta,
		PodSpec:    &pod.Spec,
	})
	if errConstructSidecar != nil {
		logrus.WithFields(logrus.Fields{
			"action": "mutationreview",
		}).Warn(errConstructSidecar.Error())
	}

	annotations := map[string]string{fmt.Sprintf("%v/status", config.Settings["annotationPrefix"]): "injected"}
	patch, errCreateMutationPatch := CreateMutationPatch(&pod, sidecar, annotations)
	if errCreateMutationPatch != nil {
		logrus.WithFields(logrus.Fields{
			"action": "mutationreview",
		}).Debugf("Failed to create mutation patch: %s", errCreateMutationPatch.Error())
		return &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: errCreateMutationPatch.Error(),
			},
		}
	}

	logrus.WithFields(logrus.Fields{
		"action":    "mutationpatch",
		"content":   string(patch),
		"namespace": req.Namespace,
		"pod":       req.Name,
		"uid":       fmt.Sprintf("%v", req.UID),
	}).Trace()

	return &admissionv1.AdmissionResponse{
		Allowed: true,
		Patch:   patch,
		PatchType: func() *admissionv1.PatchType {
			pt := admissionv1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}
