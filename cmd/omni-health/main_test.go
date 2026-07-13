package main

import "testing"

func TestMachineAddressFromURLUsesAdvertisedHostPort(t *testing.T) {
	addr, err := machineAddressFromURL("https://192.0.2.10:8090/")
	if err != nil {
		t.Fatal(err)
	}
	if addr != "192.0.2.10:8090" {
		t.Fatalf("expected advertised host:port, got %q", addr)
	}
}

func TestMachineAddressFromURLDefaultsPortWhenMissing(t *testing.T) {
	addr, err := machineAddressFromURL("https://omni.example.ts.net/")
	if err != nil {
		t.Fatal(err)
	}
	if addr != "omni.example.ts.net:8090" {
		t.Fatalf("expected default machine API port, got %q", addr)
	}
}

func TestMachineServerNameFromURLUsesAdvertisedHost(t *testing.T) {
	name, err := machineServerNameFromURL("https://192.0.2.10:8090/")
	if err != nil {
		t.Fatal(err)
	}
	if name != "192.0.2.10" {
		t.Fatalf("expected advertised host, got %q", name)
	}
}
