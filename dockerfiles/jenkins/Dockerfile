FROM jenkins/jenkins:lts-jdk21

USER root

# ============================================================
# Base packages
# ============================================================

RUN apt-get update && \
    apt-get install -y \
    ca-certificates \
    curl \
    wget \
    unzip \
    git \
    jq \
    gnupg \
    python3 \
    python3-pip \
    python3-venv \
    pipx && \
    rm -rf /var/lib/apt/lists/*

# ============================================================
# Docker CLI
# ============================================================

RUN install -m 0755 -d /etc/apt/keyrings

RUN curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg

RUN chmod a+r /etc/apt/keyrings/docker.gpg

RUN echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
> /etc/apt/sources.list.d/docker.list

RUN apt-get update && \
    apt-get install -y docker-ce-cli

# ============================================================
# Vault CLI
# ============================================================

ENV VAULT_VERSION=1.20.4

RUN wget -q https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip && \
    unzip vault_${VAULT_VERSION}_linux_amd64.zip && \
    mv vault /usr/local/bin/ && \
    chmod +x /usr/local/bin/vault && \
    rm vault_${VAULT_VERSION}_linux_amd64.zip

# ============================================================
# kubectl
# ============================================================

RUN curl -LO https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl && \
    install -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# ============================================================
# Helm
# ============================================================

RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ============================================================
# Trivy
# ============================================================

RUN wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | \
    gpg --dearmor -o /usr/share/keyrings/trivy.gpg

RUN echo \
"deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
> /etc/apt/sources.list.d/trivy.list

RUN apt-get update && \
    apt-get install -y trivy

# ============================================================
# Syft
# ============================================================

RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | \
    sh -s -- -b /usr/local/bin

# ============================================================
# Cosign
# ============================================================

RUN curl -LO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64 && \
    chmod +x cosign-linux-amd64 && \
    mv cosign-linux-amd64 /usr/local/bin/cosign

# ============================================================
# Gitleaks
# ============================================================

ENV GITLEAKS_VERSION=8.30.1

RUN wget -q https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz && \
    tar -xzf gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz && \
    mv gitleaks /usr/local/bin/ && \
    chmod +x /usr/local/bin/gitleaks && \
    rm -f gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz LICENSE README.md

# ============================================================
# Sonar Scanner
# ============================================================

ENV SONAR_SCANNER_VERSION=7.2.0.5079

RUN wget -q https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip && \
    unzip sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip -d /opt && \
    mv /opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64 /opt/sonar-scanner && \
    ln -sf /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner && \
    chmod +x /usr/local/bin/sonar-scanner && \
    rm sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip

# ============================================================
# OWASP Dependency Check
# ============================================================

ENV DC_VERSION=12.1.0

RUN wget -q https://github.com/dependency-check/DependencyCheck/releases/download/v${DC_VERSION}/dependency-check-${DC_VERSION}-release.zip && \
    unzip dependency-check-${DC_VERSION}-release.zip -d /opt && \
    mv /opt/dependency-check /opt/dependency-check-${DC_VERSION} && \
    ln -sf /opt/dependency-check-${DC_VERSION}/bin/dependency-check.sh /usr/local/bin/dependency-check && \
    chmod +x /usr/local/bin/dependency-check && \
    rm dependency-check-${DC_VERSION}-release.zip

# ============================================================
# Checkov
# ============================================================

ENV PATH="/root/.local/bin:${PATH}"

RUN pipx install checkov

USER jenkins
