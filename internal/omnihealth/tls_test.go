package omnihealth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestTLSCheckAcceptsNoSNIWhenCertificateMatchesName(t *testing.T) {
	cert, roots := testCertificate(t, "omni.example.ts.net")
	addr := startTLSServer(t, cert)

	check := TLSCheck{
		Name:       "machine-api",
		Address:    addr,
			ServerName: "omni.example.ts.net",
		SendSNI:    false,
		Timeout:    2 * time.Second,
		Roots:      roots,
	}
	if err := check.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
}

func TestTLSCheckRejectsNoSNIWhenCertificateDoesNotMatchName(t *testing.T) {
	cert, roots := testCertificate(t, "other.wind-bearded.ts.net")
	addr := startTLSServer(t, cert)

	check := TLSCheck{
		Name:       "machine-api",
		Address:    addr,
			ServerName: "omni.example.ts.net",
		SendSNI:    false,
		Timeout:    2 * time.Second,
		Roots:      roots,
	}
	if err := check.Run(context.Background()); err == nil {
		t.Fatal("expected hostname verification failure")
	}
}

func TestValidateComposeEnvRequiresEmbeddedEtcdAndCaddyCerts(t *testing.T) {
	path := filepath.Join(t.TempDir(), "compose.env")
	content := []byte(`ETCD_VOLUME_PATH=/data/etcd
SECONDARY_STORAGE_PATH=/data/secondary-storage
AUTH='--storage-kind=etcd --sqlite-storage-path=/_out/secondary-storage/omni.sqlite --etcd-embedded --etcd-embedded-db-path=/_out/etcd'
SIDEROLINK_ADVERTISED_API_URL=https://omni.example.ts.net:8090/
CADDY_TS_CERT_PATH=/opt/certs/tailscale.crt
CADDY_TS_KEY_PATH=/opt/certs/tailscale.key
`)
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := ValidateComposeEnv(path); err != nil {
		t.Fatal(err)
	}
}

func testCertificate(t *testing.T, dnsName string) (tls.Certificate, *x509.CertPool) {
	t.Helper()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}

	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: dnsName},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{dnsName},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	cert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}

	parsed, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(parsed)

	return cert, roots
}

func startTLSServer(t *testing.T, cert tls.Certificate) string {
	t.Helper()

	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func(conn net.Conn) {
				defer conn.Close()
				if tlsConn, ok := conn.(*tls.Conn); ok {
					_ = tlsConn.Handshake()
				}
			}(conn)
		}
	}()

	return listener.Addr().String()
}
