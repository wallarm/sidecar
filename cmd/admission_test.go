package main

import (
	"encoding/json"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestCheckProfile(t *testing.T) {
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
			if err := CheckProfile(&tt.config, &tt.pod); (err != nil) != tt.wantErr {
				t.Errorf("CheckProfile() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestWhetherMutate(t *testing.T) {
	config.Settings = map[string]interface{}{
		"annotationPrefix": "test",
	}

	tests := []struct {
		name        string
		annotations map[string]string
		want        bool
	}{
		{
			name:        "No annotations",
			annotations: nil,
			want:        true,
		},
		{
			name:        "Not injected",
			annotations: map[string]string{"test/status": "not-injected"},
			want:        true,
		},
		{
			name:        "Injected",
			annotations: map[string]string{"test/status": "injected"},
			want:        false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			metadata := &metav1.ObjectMeta{
				Annotations: tt.annotations,
			}
			if got := WhetherMutate(metadata); got != tt.want {
				t.Errorf("WhetherMutate() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestAddContainer(t *testing.T) {
	tests := []struct {
		name     string
		target   []corev1.Container
		added    []corev1.Container
		basePath string
		want     []PatchOperation
	}{
		{
			name:     "No target containers",
			target:   []corev1.Container{},
			added:    []corev1.Container{{Name: "test"}},
			basePath: "/spec/containers",
			want: []PatchOperation{
				{
					Op:    "add",
					Path:  "/spec/containers",
					Value: []corev1.Container{{Name: "test"}},
				},
			},
		},
		{
			name:     "With target containers",
			target:   []corev1.Container{{Name: "existing"}},
			added:    []corev1.Container{{Name: "test"}},
			basePath: "/spec/containers",
			want: []PatchOperation{
				{
					Op:    "add",
					Path:  "/spec/containers/-",
					Value: corev1.Container{Name: "test"},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := AddContainer(tt.target, tt.added, tt.basePath); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("AddContainer() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestAddVolume(t *testing.T) {
	tests := []struct {
		name     string
		target   []corev1.Volume
		added    []corev1.Volume
		basePath string
		want     []PatchOperation
	}{
		{
			name:     "No target volumes",
			target:   []corev1.Volume{},
			added:    []corev1.Volume{{Name: "test"}},
			basePath: "/spec/volumes",
			want: []PatchOperation{
				{
					Op:    "add",
					Path:  "/spec/volumes",
					Value: []corev1.Volume{{Name: "test"}},
				},
			},
		},
		{
			name:     "With target volumes",
			target:   []corev1.Volume{{Name: "existing"}},
			added:    []corev1.Volume{{Name: "test"}},
			basePath: "/spec/volumes",
			want: []PatchOperation{
				{
					Op:    "add",
					Path:  "/spec/volumes/-",
					Value: corev1.Volume{Name: "test"},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := AddVolume(tt.target, tt.added, tt.basePath); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("AddVolume() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestUpdateAnnotation(t *testing.T) {
	tests := []struct {
		name   string
		target map[string]string
		added  map[string]string
		want   []PatchOperation
	}{
		{
			name:   "No target annotations",
			target: nil,
			added:  map[string]string{"test/key": "test-value"},
			want: []PatchOperation{
				{
					Op:   "add",
					Path: "/metadata/annotations",
					Value: map[string]string{
						"test/key": "test-value",
					},
				},
			},
		},
		{
			name:   "With target annotations",
			target: map[string]string{"existing/key": "existing-value"},
			added:  map[string]string{"test/key": "test-value"},
			want: []PatchOperation{
				{
					Op:    "add",
					Path:  "/metadata/annotations/test~1key",
					Value: "test-value",
				},
			},
		},
		{
			name:   "Replace existing annotation",
			target: map[string]string{"test/key": "existing-value"},
			added:  map[string]string{"test/key": "test-value"},
			want: []PatchOperation{
				{
					Op:    "replace",
					Path:  "/metadata/annotations/test~1key",
					Value: "test-value",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := UpdateAnnotation(tt.target, tt.added); !reflect.DeepEqual(got, tt.want) {
				t.Errorf("UpdateAnnotation() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCreateMutationPatch(t *testing.T) {
	tests := []struct {
		name        string
		pod         corev1.Pod
		sidecar     Sidecar
		annotations map[string]string
		want        []byte
		wantErr     bool
	}{
		{
			name: "Basic test",
			pod: corev1.Pod{
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{Name: "existing"}},
				},
			},
			sidecar: Sidecar{
				Containers: []corev1.Container{{Name: "sidecar"}},
			},
			annotations: map[string]string{"test/key": "test-value"},
			want: func() []byte {
				patch := []PatchOperation{
					{
						Op:    "add",
						Path:  "/spec/containers/-",
						Value: corev1.Container{Name: "sidecar"},
					},
					{
						Op:   "add",
						Path: "/metadata/annotations",
						Value: map[string]string{
							"test/key": "test-value",
						},
					},
				}
				b, _ := json.Marshal(patch)
				return b
			}(),
			wantErr: false,
		},
		{
			name: "Add sidecar container and annotation",
			pod: corev1.Pod{
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{Name: "existing"}},
				},
			},
			sidecar: Sidecar{
				Containers: []corev1.Container{{Name: "sidecar"}},
			},
			annotations: map[string]string{"test/key": "test-value"},
			want: func() []byte {
				patch := []PatchOperation{
					{
						Op:    "add",
						Path:  "/spec/containers/-",
						Value: corev1.Container{Name: "sidecar"},
					},
					{
						Op:   "add",
						Path: "/metadata/annotations",
						Value: map[string]string{
							"test/key": "test-value",
						},
					},
				}
				b, _ := json.Marshal(patch)
				return b
			}(),
			wantErr: false,
		},
		{
			name: "Add volume and replace annotation",
			pod: corev1.Pod{
				Spec: corev1.PodSpec{
					Volumes: []corev1.Volume{{Name: "existing"}},
				},
				ObjectMeta: metav1.ObjectMeta{
					Annotations: map[string]string{"test/key": "old-value"},
				},
			},
			sidecar: Sidecar{
				Volumes: []corev1.Volume{{Name: "sidecar"}},
			},
			annotations: map[string]string{"test/key": "new-value"},
			want: func() []byte {
				patch := []PatchOperation{
					{
						Op:    "add",
						Path:  "/spec/volumes/-",
						Value: corev1.Volume{Name: "sidecar"},
					},
					{
						Op:    "replace",
						Path:  "/metadata/annotations/test~1key",
						Value: "new-value",
					},
				}
				b, _ := json.Marshal(patch)
				return b
			}(),
			wantErr: false,
		},
		{
			name: "Add init container, no existing annotations",
			pod: corev1.Pod{
				Spec: corev1.PodSpec{
					InitContainers: []corev1.Container{{Name: "existing"}},
				},
			},
			sidecar: Sidecar{
				InitContainers: []corev1.Container{{Name: "sidecar"}},
			},
			annotations: map[string]string{"test/key": "test-value"},
			want: func() []byte {
				patch := []PatchOperation{
					{
						Op:    "add",
						Path:  "/spec/initContainers/-",
						Value: corev1.Container{Name: "sidecar"},
					},
					{
						Op:   "add",
						Path: "/metadata/annotations",
						Value: map[string]string{
							"test/key": "test-value",
						},
					},
				}
				b, _ := json.Marshal(patch)
				return b
			}(),
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := CreateMutationPatch(&tt.pod, &tt.sidecar, tt.annotations)
			if (err != nil) != tt.wantErr {
				t.Errorf("CreateMutationPatch() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("CreateMutationPatch() = %v, want %v", string(got), string(tt.want))
			}
		})
	}
}
