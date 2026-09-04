// Package releasedispatch validates the controller's repository_dispatch contract.
package releasedispatch

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"regexp"
)

const (
	ControllerRepository = "syscode-labs/talos-release-controller"
	SourceRepository     = "syscode-labs/syscode-homelab-gitops-apps"
	InstallerRepository  = "ghcr.io/syscode-labs/talos-images/installer"
)

var (
	releaseIDRE    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`)
	versionRE      = regexp.MustCompile(`^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$`)
	shaRE          = regexp.MustCompile(`^[0-9a-f]{40}$`)
	digestRE       = regexp.MustCompile(`^sha256:[0-9a-f]{64}$`)
	ociImageOCIDRE = regexp.MustCompile(`^ocid1\.image\.[A-Za-z0-9._-]+$`)
)

type Artifact struct {
	Ref    string `json:"ref"`
	Digest string `json:"digest"`
}

type OCIArtifact struct {
	Artifact
	ImageOCID string `json:"image_ocid"`
}

type Artifacts struct {
	Unraid Artifact    `json:"unraid"`
	OCI    OCIArtifact `json:"oci"`
}

type Request struct {
	ReleaseID         string    `json:"release_id"`
	SourceRepo        string    `json:"source_repo"`
	SourceSHA         string    `json:"source_sha"`
	SenderRepo        string    `json:"sender_repo"`
	TalosVersion      string    `json:"talos_version"`
	KubernetesVersion string    `json:"kubernetes_version"`
	IdempotencyKey    string    `json:"idempotency_key"`
	BuildRunID        int64     `json:"build_run_id"`
	Artifacts         Artifacts `json:"artifacts"`
}

func Parse(payload []byte) (Request, error) {
	var request Request
	decoder := json.NewDecoder(bytes.NewReader(payload))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return Request{}, fmt.Errorf("parse request: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return Request{}, fmt.Errorf("parse request: trailing data")
	}
	if !releaseIDRE.MatchString(request.ReleaseID) {
		return Request{}, fmt.Errorf("invalid release_id")
	}
	if request.SenderRepo != ControllerRepository {
		return Request{}, fmt.Errorf("unexpected sender_repo")
	}
	if request.SourceRepo != SourceRepository || !shaRE.MatchString(request.SourceSHA) {
		return Request{}, fmt.Errorf("invalid immutable release source")
	}
	if !versionRE.MatchString(request.TalosVersion) || !versionRE.MatchString(request.KubernetesVersion) {
		return Request{}, fmt.Errorf("invalid requested version")
	}
	if request.IdempotencyKey != request.ReleaseID {
		return Request{}, fmt.Errorf("idempotency_key must equal release_id")
	}
	if request.BuildRunID <= 0 {
		return Request{}, fmt.Errorf("build_run_id must be positive")
	}
	artifact := request.Artifacts.Unraid
	if artifact.Ref != InstallerRepository+":"+request.TalosVersion+"-libvirt" || !digestRE.MatchString(artifact.Digest) {
		return Request{}, fmt.Errorf("invalid immutable Unraid libvirt artifact")
	}
	oci := request.Artifacts.OCI
	if oci.Ref != InstallerRepository+":"+request.TalosVersion || !digestRE.MatchString(oci.Digest) || !ociImageOCIDRE.MatchString(oci.ImageOCID) {
		return Request{}, fmt.Errorf("invalid immutable OCI artifact")
	}
	return request, nil
}

func (r Request) InstallerImage() string {
	return r.Artifacts.Unraid.Ref + "@" + r.Artifacts.Unraid.Digest
}
