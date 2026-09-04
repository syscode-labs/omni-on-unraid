package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"

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
	runID, err := strconv.ParseInt(os.Getenv("GITHUB_RUN_ID"), 10, 64)
	if err != nil {
		fail(fmt.Errorf("parse GITHUB_RUN_ID: %w", err))
	}
	url := os.Getenv("GITHUB_SERVER_URL") + "/" + os.Getenv("GITHUB_REPOSITORY") + "/actions/runs/" + os.Getenv("GITHUB_RUN_ID")
	result, err := releasedispatch.Result(request, os.Getenv("OUTCOME"), runID, url)
	if err != nil {
		fail(err)
	}
	if err := json.NewEncoder(os.Stdout).Encode(map[string]any{"event_type": "talos-release-result", "client_payload": result}); err != nil {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
