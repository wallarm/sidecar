package main

import (
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestCheckConfigAndPod(t *testing.T) {
	tests := []struct {
		name    string
		config  Config
		pod     corev1.Pod
		wantErr bool
	}{
		{
			name: "No annotation prefix",
			config: Config{
				Settings: map[string]interface{}{},
			},
			pod:     corev1.Pod{},
			wantErr: true,
		},
		{
			name: "No profile annotation",
			config: Config{
				Settings: map[string]interface{}{
					"annotationPrefix": "test",
				},
			},
			pod:     corev1.Pod{},
			wantErr: false,
		},
		{
			name: "No config profiles",
			config: Config{
				Settings: map[string]interface{}{
					"annotationPrefix": "test",
				},
			},
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Annotations: map[string]string{
						"test/profile": "test-profile",
					},
				},
			},
			wantErr: true,
		},
		{
			name: "Profile not in config",
			config: Config{
				Settings: map[string]interface{}{
					"annotationPrefix": "test",
					"profiles": map[string]interface{}{
						"other-profile": map[string]interface{}{},
					},
				},
			},
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Annotations: map[string]string{
						"test/profile": "test-profile",
					},
				},
			},
			wantErr: true,
		},
		{
			name: "Empty profile in config",
			config: Config{
				Settings: map[string]interface{}{
					"annotationPrefix": "test",
					"profiles": map[string]interface{}{
						"test-profile": map[string]interface{}{},
					},
				},
			},
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Annotations: map[string]string{
						"test/profile": "test-profile",
					},
				},
			},
			wantErr: true,
		},
		{
			name: "Profile in config",
			config: Config{
				Settings: map[string]interface{}{
					"annotationPrefix": "test",
					"profiles": map[string]interface{}{
						"test-profile": map[string]interface{}{
							"param": "value",
						},
					},
				},
			},
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					Annotations: map[string]string{
						"test/profile": "test-profile",
					},
				},
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := CheckConfigAndPod(&tt.config, &tt.pod); (err != nil) != tt.wantErr {
				t.Errorf("CheckConfigAndPod() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}
