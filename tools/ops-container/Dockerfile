FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.local/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    make \
    openssh-client \
    rsync \
    libvirt-clients \
    genisoimage \
    gnupg \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm -f /tmp/terraform.zip

# mise task runner (keeps container UX identical to host)
RUN curl -fsSL https://mise.run | sh

WORKDIR /workspace
ENTRYPOINT ["/bin/bash", "-lc"]
