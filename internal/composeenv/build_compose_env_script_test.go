package composeenv_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestBuildComposeEnvGeneratesCertificateWithSideroLinkSANs(t *testing.T) {
	repoRoot := findRepoRoot(t)
	tempRoot := copyScripts(t, repoRoot, "build-compose-env.sh")

	envFile := filepath.Join(tempRoot, ".env")
	env := strings.Join([]string{
		"OMNI_DOMAIN=omni.example.ts.net",
		"OMNI_DATA_DIR=" + filepath.Join(tempRoot, "data"),
		"OMNI_SIDEROLINK_API_URL=https://192.0.2.10:8090/",
		"OMNI_WG_ADDR=192.0.2.10:50180",
		"",
	}, "\n")
	if err := os.WriteFile(envFile, []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	runScript(t, tempRoot, "build-compose-env.sh")

	certPath := filepath.Join(tempRoot, "data", "tls", "tls.crt")
	openssl := exec.Command("openssl", "x509", "-in", certPath, "-noout", "-ext", "subjectAltName")
	certOutput, err := openssl.CombinedOutput()
	if err != nil {
		t.Fatalf("inspect certificate SAN failed: %v\n%s", err, certOutput)
	}

	san := string(certOutput)
	if !strings.Contains(san, "DNS:omni.example.ts.net") {
		t.Fatalf("certificate SAN missing Omni DNS name:\n%s", san)
	}
	if !strings.Contains(san, "IP Address:192.0.2.10") {
		t.Fatalf("certificate SAN missing SideroLink IP:\n%s", san)
	}
}

func TestCaddySNIModeProxiesMachineAPI(t *testing.T) {
	repoRoot := findRepoRoot(t)
	tempRoot := copyScripts(t, repoRoot, "build-compose-env.sh", "build-caddy-config.sh")

	envFile := filepath.Join(tempRoot, ".env")
	env := strings.Join([]string{
		"OMNI_DOMAIN=omni.example.ts.net",
		"OMNI_DATA_DIR=" + filepath.Join(tempRoot, "data"),
		"OMNI_TLS_MODE=caddy-sni",
		"OMNI_TS_DOMAIN=omni.example.ts.net",
		"OMNI_TS_IP=100.64.0.10",
		"",
	}, "\n")
	if err := os.WriteFile(envFile, []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	runScript(t, tempRoot, "build-compose-env.sh")
	runScript(t, tempRoot, "build-caddy-config.sh")

	envOutput, err := os.ReadFile(filepath.Join(tempRoot, "generated", "compose.env"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(envOutput), "MACHINE_API_BIND_ADDR=127.0.0.1:8092") {
		t.Fatalf("caddy-sni mode should bind Omni machine API to loopback:\n%s", envOutput)
	}
	if !strings.Contains(string(envOutput), "SIDEROLINK_ADVERTISED_API_URL=https://omni.example.ts.net:8090/") {
		t.Fatalf("caddy-sni mode should advertise the TLS DNS endpoint:\n%s", envOutput)
	}
	if !strings.Contains(string(envOutput), "SIDEROLINK_WIREGUARD_ADVERTISED_ADDR=100.64.0.10:50180") {
		t.Fatalf("caddy-sni mode should advertise the Tailscale WireGuard IP endpoint:\n%s", envOutput)
	}

	caddyfile, err := os.ReadFile(filepath.Join(tempRoot, "generated", "caddy", "Caddyfile"))
	if err != nil {
		t.Fatal(err)
	}
	caddy := string(caddyfile)
	if !strings.Contains(caddy, "omni.example.ts.net:8090") {
		t.Fatalf("Caddyfile missing SideroLink machine API listener:\n%s", caddy)
	}
	if !strings.Contains(caddy, "default_sni omni.example.ts.net") {
		t.Fatalf("Caddyfile should default no-SNI clients to the Tailscale DNS name:\n%s", caddy)
	}
	if !strings.Contains(caddy, "fallback_sni omni.example.ts.net") {
		t.Fatalf("Caddyfile should fallback unmatched SNI clients to the Tailscale DNS name:\n%s", caddy)
	}
	if !strings.Contains(caddy, "tls /opt/certs/tailscale.crt /opt/certs/tailscale.key") {
		t.Fatalf("Caddyfile should load the Tailscale cert for no-SNI machine API clients:\n%s", caddy)
	}
	if !strings.Contains(caddy, "reverse_proxy https://127.0.0.1:8092") {
		t.Fatalf("Caddyfile missing SideroLink machine API upstream:\n%s", caddy)
	}
}

func TestBuildComposeEnvCanUseExternalOmniTLSCertificate(t *testing.T) {
	repoRoot := findRepoRoot(t)
	tempRoot := copyScripts(t, repoRoot, "build-compose-env.sh")

	envFile := filepath.Join(tempRoot, ".env")
	env := strings.Join([]string{
		"OMNI_DOMAIN=omni.example.ts.net",
		"OMNI_DATA_DIR=" + filepath.Join(tempRoot, "data"),
		"OMNI_TLS_CERT_FILE=" + filepath.Join(tempRoot, "generated", "certs", "tailscale.crt"),
		"OMNI_TLS_KEY_FILE=" + filepath.Join(tempRoot, "generated", "certs", "tailscale.key"),
		"",
	}, "\n")
	if err := os.WriteFile(envFile, []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	runScript(t, tempRoot, "build-compose-env.sh")

	envOutput, err := os.ReadFile(filepath.Join(tempRoot, "generated", "compose.env"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(envOutput), "TLS_CERT="+filepath.Join(tempRoot, "generated", "certs", "tailscale.crt")) {
		t.Fatalf("compose env should mount the configured Omni TLS cert:\n%s", envOutput)
	}
	if !strings.Contains(string(envOutput), "TLS_KEY="+filepath.Join(tempRoot, "generated", "certs", "tailscale.key")) {
		t.Fatalf("compose env should mount the configured Omni TLS key:\n%s", envOutput)
	}
}

func TestBuildComposeEnvDefaultsToEmbeddedEtcdStorage(t *testing.T) {
	repoRoot := findRepoRoot(t)
	tempRoot := copyScripts(t, repoRoot, "build-compose-env.sh")

	envFile := filepath.Join(tempRoot, ".env")
	env := strings.Join([]string{
		"OMNI_DOMAIN=omni.example.ts.net",
		"OMNI_DATA_DIR=" + filepath.Join(tempRoot, "data"),
		"",
	}, "\n")
	if err := os.WriteFile(envFile, []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	runScript(t, tempRoot, "build-compose-env.sh")

	envOutput, err := os.ReadFile(filepath.Join(tempRoot, "generated", "compose.env"))
	if err != nil {
		t.Fatal(err)
	}
	output := string(envOutput)
	if !strings.Contains(output, "--storage-kind=etcd") {
		t.Fatalf("compose env should default Omni to etcd storage:\n%s", output)
	}
	if !strings.Contains(output, "--etcd-embedded") {
		t.Fatalf("compose env should enable embedded etcd by default:\n%s", output)
	}
	if !strings.Contains(output, "--etcd-embedded-db-path=/_out/etcd") {
		t.Fatalf("compose env should persist embedded etcd under /_out/etcd:\n%s", output)
	}
	if !strings.Contains(output, "--sqlite-storage-path=/_out/secondary-storage/omni.sqlite") {
		t.Fatalf("compose env should keep Omni sqlite support path on persistent secondary-storage:\n%s", output)
	}
}

func TestBuildComposeEnvCanSetImageFactoryAddress(t *testing.T) {
	repoRoot := findRepoRoot(t)
	tempRoot := copyScripts(t, repoRoot, "build-compose-env.sh")

	envFile := filepath.Join(tempRoot, ".env")
	env := strings.Join([]string{
		"OMNI_DOMAIN=omni.example.ts.net",
		"OMNI_DATA_DIR=" + filepath.Join(tempRoot, "data"),
		"OMNI_IMAGE_FACTORY_ADDRESS=https://factory.example.ts.net",
		"",
	}, "\n")
	if err := os.WriteFile(envFile, []byte(env), 0o600); err != nil {
		t.Fatal(err)
	}

	runScript(t, tempRoot, "build-compose-env.sh")

	envOutput, err := os.ReadFile(filepath.Join(tempRoot, "generated", "compose.env"))
	if err != nil {
		t.Fatal(err)
	}
	output := string(envOutput)
	if !strings.Contains(output, "--image-factory-address=https://factory.example.ts.net") {
		t.Fatalf("compose env should configure Omni image factory address:\n%s", output)
	}
}

func copyScripts(t *testing.T, repoRoot string, names ...string) string {
	t.Helper()

	tempRoot := t.TempDir()
	tempScripts := filepath.Join(tempRoot, "scripts")
	if err := os.MkdirAll(tempScripts, 0o755); err != nil {
		t.Fatal(err)
	}

	for _, name := range names {
		sourceScript := filepath.Join(repoRoot, "scripts", name)
		scriptBytes, err := os.ReadFile(sourceScript)
		if err != nil {
			t.Fatal(err)
		}
		tempScript := filepath.Join(tempScripts, name)
		if err := os.WriteFile(tempScript, scriptBytes, 0o755); err != nil {
			t.Fatal(err)
		}
	}

	return tempRoot
}

func runScript(t *testing.T, root, name string) {
	t.Helper()

	cmd := exec.Command("bash", filepath.Join(root, "scripts", name))
	cmd.Dir = root
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s failed: %v\n%s", name, err, output)
	}
}

func findRepoRoot(t *testing.T) string {
	t.Helper()

	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}

	dir := filepath.Dir(filename)
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("could not find repo root")
		}
		dir = parent
	}
}
