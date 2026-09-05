package main

import (
	"fmt"
	"io"
	"os"

	"github.com/syscode-labs/omni-on-unraid/internal/releasedispatch"
)

func main() {
	payload, err := io.ReadAll(os.Stdin)
	if err != nil {
		fail(err)
	}
	request, err := releasedispatch.Parse(payload)
	if err != nil {
		fail(err)
	}
	for _, value := range []string{
		"RELEASE_ID=" + request.ReleaseID,
		"RELEASE_SOURCE_REPO=" + request.SourceRepo,
		"RELEASE_SOURCE_SHA=" + request.SourceSHA,
		"RELEASE_TALOS_VERSION=" + request.TalosVersion,
		"RELEASE_KUBERNETES_VERSION=" + request.KubernetesVersion,
		"RELEASE_BUILD_RUN_ID=" + fmt.Sprint(request.BuildRunID),
		"RELEASE_INSTALL_IMAGE=" + request.InstallerImage(),
	} {
		fmt.Println(value)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
