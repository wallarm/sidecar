package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	"github.com/sirupsen/logrus"
	admissionv1 "k8s.io/api/admission/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func InjectHandlerFunc(w http.ResponseWriter, r *http.Request) {
	var body []byte
	if r.Body != nil {
		if data, err := io.ReadAll(r.Body); err == nil {
			body = data
		}
	}
	if len(body) == 0 {
		errmsg := "Empty body received"
		logrus.WithFields(logrus.Fields{
			"action": "injecthandler",
		}).Debug(errmsg)
		http.Error(w, errmsg, http.StatusBadRequest)
		return
	}

	// Preflight check
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		errmsg := fmt.Sprintf("Bad content-type header in request: found \"%s\", expected \"application/json\"", contentType)
		logrus.WithFields(logrus.Fields{
			"action": "injecthandler",
		}).Debug(errmsg)
		http.Error(w, errmsg, http.StatusUnsupportedMediaType)
		return
	}

	var admissionResponse *admissionv1.AdmissionResponse
	ar := admissionv1.AdmissionReview{}

	if _, _, err := config.Deserializer.Decode(body, nil, &ar); err != nil {
		errmsg := fmt.Sprintf("Failed to decode body: %s", err.Error())
		logrus.WithFields(logrus.Fields{
			"action": "injecthandler",
		}).Debug(errmsg)
		admissionResponse = &admissionv1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	} else {
		admissionResponse = Mutate(&ar)
	}

	admissionReview := admissionv1.AdmissionReview{
		TypeMeta: metav1.TypeMeta{
			APIVersion: "admission.k8s.io/v1",
			Kind:       "AdmissionReview",
		},
	}
	if admissionResponse != nil {
		admissionReview.Response = admissionResponse
		if ar.Request != nil {
			admissionReview.Response.UID = ar.Request.UID
		}
	}

	resp, errMarshal := json.Marshal(admissionReview)
	if errMarshal != nil {
		errmsg := fmt.Sprintf("Failed to encode response: %s", errMarshal.Error())
		logrus.WithFields(logrus.Fields{
			"action": "injecthandler",
		}).Debug(errmsg)
		http.Error(w, errmsg, http.StatusInternalServerError)
	}

	if _, errWrite := w.Write(resp); errWrite != nil {
		errmsg := fmt.Sprintf("Failed to write response: %s", errWrite.Error())
		logrus.WithFields(logrus.Fields{
			"action": "injecthandler",
		}).Debug(errmsg)
		http.Error(w, errmsg, http.StatusInternalServerError)
	}
}
