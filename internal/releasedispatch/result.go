package releasedispatch

import "fmt"

type Callback struct {
	ReleaseID  string    `json:"release_id"`
	Provider   string    `json:"provider"`
	Outcome    string    `json:"outcome"`
	SourceRepo string    `json:"source_repo"`
	SourceSHA  string    `json:"source_sha"`
	RunID      int64     `json:"run_id"`
	BuildRunID int64     `json:"build_run_id"`
	Artifacts  Artifacts `json:"artifacts"`
	DetailsURL    string    `json:"details_url"`
	AttemptState  string    `json:"attempt_state,omitempty"`
}

func Result(request Request, outcome string, runID int64, detailsURL, attemptState string) (Callback, error) {
	if outcome != "success" && outcome != "failure" {
		return Callback{}, fmt.Errorf("invalid rollout outcome")
	}
	if runID <= 0 || detailsURL == "" {
		return Callback{}, fmt.Errorf("invalid callback run identity")
	}
	if attemptState != "" && attemptState != "failed_pre_mutation" && attemptState != "existing_claim" {
		return Callback{}, fmt.Errorf("invalid recovery attempt state")
	}
	if attemptState != "" && outcome != "failure" {
		return Callback{}, fmt.Errorf("recovery attempt state requires a failed rollout")
	}
	return Callback{
		ReleaseID: request.ReleaseID, Provider: "omni-on-unraid", Outcome: outcome,
		SourceRepo: request.SourceRepo, SourceSHA: request.SourceSHA, RunID: runID,
		BuildRunID: request.BuildRunID, Artifacts: request.Artifacts, DetailsURL: detailsURL, AttemptState: attemptState,
	}, nil
}
