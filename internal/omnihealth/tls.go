package omnihealth

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

type TLSCheck struct {
	Name       string
	Address    string
	ServerName string
	SendSNI    bool
	Timeout    time.Duration
	Roots      *x509.CertPool
}

func (c TLSCheck) Run(ctx context.Context) error {
	if c.Address == "" {
		return fmt.Errorf("%s address is required", c.Name)
	}
	if c.ServerName == "" {
		return fmt.Errorf("%s server name is required", c.Name)
	}
	timeout := c.Timeout
	if timeout == 0 {
		timeout = 10 * time.Second
	}

	dialer := &net.Dialer{Timeout: timeout}
	tcpConn, err := dialer.DialContext(ctx, "tcp", c.Address)
	if err != nil {
		return fmt.Errorf("%s tcp connect %s: %w", c.Name, c.Address, err)
	}
	defer tcpConn.Close()

	config := &tls.Config{
		MinVersion: tls.VersionTLS12,
		RootCAs:    c.Roots,
	}
	if c.SendSNI {
		config.ServerName = c.ServerName
	} else {
		config.InsecureSkipVerify = true
	}

	tlsConn := tls.Client(tcpConn, config)
	defer tlsConn.Close()

	handshakeCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	if err := tlsConn.HandshakeContext(handshakeCtx); err != nil {
		return fmt.Errorf("%s tls handshake %s: %w", c.Name, c.Address, err)
	}

	state := tlsConn.ConnectionState()
	if len(state.PeerCertificates) == 0 {
		return fmt.Errorf("%s tls handshake returned no peer certificate", c.Name)
	}

	if !c.SendSNI {
		opts := x509.VerifyOptions{
			DNSName: c.ServerName,
			Roots:   c.Roots,
		}
		if _, err := state.PeerCertificates[0].Verify(opts); err != nil {
			return fmt.Errorf("%s no-SNI certificate verification for %s: %w", c.Name, c.ServerName, err)
		}
	}

	return nil
}

func ValidateComposeEnv(path string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read compose env %s: %w", path, err)
	}
	text := string(content)
	required := []string{
		"ETCD_VOLUME_PATH=",
		"SECONDARY_STORAGE_PATH=",
		"--storage-kind=etcd",
		"--sqlite-storage-path=/_out/secondary-storage/omni.sqlite",
		"--etcd-embedded",
		"--etcd-embedded-db-path=/_out/etcd",
		"SIDEROLINK_ADVERTISED_API_URL=https://",
		"CADDY_TS_CERT_PATH=/opt/certs/tailscale.crt",
		"CADDY_TS_KEY_PATH=/opt/certs/tailscale.key",
	}
	for _, item := range required {
		if !strings.Contains(text, item) {
			return fmt.Errorf("compose env missing %q", item)
		}
	}
	return nil
}
