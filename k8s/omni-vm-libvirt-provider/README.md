# Omni VM Libvirt Provider

This deploys the official Omni libvirt infrastructure provider onto Kubernetes
running on the Omni VM. It lets Omni request Talos machines from libvirt through
an Omni `MachineClass`.

Secrets are not stored in this repo.

Create provider credentials in Omni:

1. Open Omni.
2. Go to `Settings -> Infra Providers`.
3. Create or renew provider `libvirt`.
4. Save `OMNI_ENDPOINT` and `OMNI_SERVICE_ACCOUNT_KEY` into a Kubernetes Secret.

Create required secrets in the Omni VM Kubernetes cluster:

```bash
kubectl create namespace omni-infra-provider --dry-run=client -o yaml | kubectl apply -f -
kubectl -n omni-infra-provider create secret generic omni-infra-provider-libvirt \
  --from-literal=OMNI_ENDPOINT=https://omni.example.internal \
  --from-literal=OMNI_SERVICE_ACCOUNT_KEY='<service-account-key>' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n omni-infra-provider create secret generic omni-infra-provider-libvirt-ssh \
  --from-file=id_rsa=/path/to/provider/private/key \
  --dry-run=client -o yaml | kubectl apply -f -
```

Deploy provider:

```bash
mise run omni:provider:apply
kubectl -n omni-infra-provider rollout status deployment/omni-infra-provider-libvirt
```

The libvirt provider assumes libvirt networks and storage pools already exist.
For Unraid, the lab overlay expects a libvirt network named `default` and storage
pool configured in the Omni `MachineClass`.
