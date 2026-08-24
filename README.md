# DevSecOps Platform

Plateforme DevSecOps privée pour l'automatisation des processus CI/CD, réalisée dans le cadre d'un Projet de Fin d'Année (PFA).

Le projet met en place une chaîne CI/CD complète intégrant les bonnes pratiques DevSecOps : qualité du code, sécurité applicative, sécurité des images Docker, déploiement automatisé sur Kubernetes et supervision de l'infrastructure.

## Sommaire

- [Contexte](#contexte)
- [Architecture générale](#architecture-générale)
- [Stack technique](#stack-technique)
- [Versions des outils](#versions-des-outils)
- [Pipeline CI/CD](#pipeline-cicd)
- [Déclenchement automatique du pipeline (Webhook + Smee)](#déclenchement-automatique-du-pipeline-webhook--smee)
- [Jenkins Credentials](#jenkins-credentials)
- [Gestion des secrets avec Vault](#gestion-des-secrets-avec-vault)
- [Base de données de l'application (Laragon)](#base-de-données-de-lapplication-laragon)
- [Structure du dépôt](#structure-du-dépôt)
- [Sécurité du déploiement Kubernetes](#sécurité-du-déploiement-kubernetes)
- [Kyverno — Policy Engine](#kyverno--policy-engine)
- [Monitoring et observabilité](#monitoring-et-observabilité)
- [Persistance des données](#persistance-des-données)
- [Installation](#installation)
- [Mise en production — ce qui reste à durcir](#mise-en-production--ce-qui-reste-à-durcir)
- [État d'avancement](#état-davancement)
- [Évolutions prévues](#évolutions-prévues)

## Contexte

Les déploiements manuels présentent plusieurs limites : absence d'automatisation, erreurs humaines, détection tardive des vulnérabilités, absence de contrôle continu de la qualité du code, manque de traçabilité et difficulté à superviser les applications en production.

Ce projet vise à automatiser l'ensemble du cycle de développement d'une application web Laravel, en intégrant des contrôles de sécurité dès les premières étapes du pipeline, jusqu'au déploiement supervisé sur Kubernetes.

La plateforme repose sur deux machines virtuelles Ubuntu Server, séparant les outils DevSecOps de l'environnement d'exécution.

## Architecture générale

```
Développeur (Git Push)
        │
        ▼
┌───────────────────────────────┐        ┌───────────────────────────────┐
│   VM1 — Plateforme DevSecOps  │        │   VM2 — Plateforme Kubernetes │
│                                │        │                                │
│  GitHub (SCM)                  │        │  k3s (cluster Kubernetes)      │
│  Jenkins (CI/CD)                │───────▶│  Helm (déploiement)            │
│  SonarQube · Gitleaks           │ Image  │  Traefik (Ingress Controller)  │
│  OWASP Dependency-Check         │ signée │  Kyverno (Policy Engine)       │
│  Checkov                        │ Helm   │  Application Laravel           │
│  Docker Engine (build)          │ Deploy │  Prometheus · Loki             │
│  Trivy · Syft · Cosign          │        │  Grafana · Alertmanager        │
│  Vault (secrets)                │        │                                │
│  Docker Hub (registre)          │        │                                │
└───────────────────────────────┘        └───────────────────────────────┘
```

Cette séparation permet :
- d'isoler la plateforme DevSecOps de l'environnement d'exécution,
- de reproduire une architecture proche des pratiques utilisées en entreprise,
- de faciliter la maintenance et de limiter l'impact d'une panne,
- de préparer une migration future vers un VPS privé.

## Stack technique

| Outil | Catégorie | Rôle |
|---|---|---|
| GitHub | SCM | Hébergement du code source, déclenchement du pipeline via webhook |
| Jenkins | CI/CD | Orchestration complète du pipeline |
| SonarQube | SAST | Analyse de la qualité du code |
| Gitleaks | Secret Scanning | Détection des secrets dans le dépôt Git |
| OWASP Dependency-Check | SCA | Analyse des dépendances vulnérables |
| Checkov | IaC Security | Analyse du Dockerfile et du Helm Chart |
| Docker | Conteneurisation | Construction d'images Docker |
| Trivy | Container Security | Analyse des vulnérabilités (filesystem et image) |
| Syft | SBOM | Génération de la nomenclature logicielle (SPDX, CycloneDX) |
| Cosign | Image Signing | Signature numérique des images |
| Docker Hub | Registry | Stockage et distribution des images Docker |
| Vault | Secrets Management | Gestion centralisée des secrets |
| k3s | Kubernetes | Orchestration des conteneurs (cluster single-node) |
| Helm | Kubernetes | Déploiement et gestion des applications |
| Traefik | Ingress Controller | Publication des services |
| Kyverno | Policy Engine | Validation des politiques de sécurité Kubernetes |
| Prometheus | Monitoring | Collecte des métriques |
| Alertmanager | Alerting | Gestion des alertes |
| Grafana | Dashboard | Visualisation des métriques et journaux |
| Loki | Logging | Centralisation des journaux applicatifs |
| Promtail | Log shipping | Collecte des journaux depuis tous les pods du cluster |
| Node Exporter | Monitoring | Surveillance des ressources système |
| kube-state-metrics | Monitoring | Surveillance des objets Kubernetes |

> **Note** : le registre d'images a évolué de Nexus (prévu initialement) vers **Docker Hub** en cours de projet, pour simplifier l'intégration. Le traçage distribué (Jaeger, OpenTelemetry Collector) n'a pas été retenu dans le périmètre final.

## Versions des outils

| Outil | Version |
|---|---|
| Jenkins | `lts-jdk21` |
| Docker CLI | 29.6.1 |
 Docker compose |v5.3.1 |
| HashiCorp Vault | 1.20.4 |
| kubectl | v5.8.1 |
| Helm | v3.21.3 |
| Trivy | 0.71.2 |
| Syft | v1.34.2 |
| Cosign | v3.1.2|
| Gitleaks | 8.28.0 → 8.30.1 |
| Sonar Scanner CLI | 7.2.0.5079 |
| OWASP Dependency-Check | 12.1.0 |
| Checkov | 3.3.8 (installé via `pipx`) |
| k3s | v1.36.3+k3s1 (Kubernetes v1.36.3) |
| Kyverno | v1.18.2  |
| kube-prometheus-stack | chart |
| Grafana  |
| Loki  |
| Node.js v22.22.1/ npm 9.2.0 | requis pour `smee-client` |
| smee-client | 5.0.0 (`npm install -g smee-client`) |

> Les versions exactes sont figées dans `dockerfiles/jenkins/Dockerfile` (variables `ENV`) pour garantir la reproductibilité de l'environnement Jenkins.

## Pipeline CI/CD

Le pipeline Jenkins est déclenché automatiquement après chaque `git push` sur le dépôt applicatif, via webhook (relayé par [smee.io](https://smee.io) pour l'environnement de développement local).

```
Initialization
    │
    ▼
Checkout Application ──▶ Verify Application ──▶ Detect Project
    │
    ▼
Retrieve Secrets (Vault)
    │
    ▼
Build Application
    │
    ▼
SonarQube Analysis ──▶ OWASP Dependency-Check ──▶ Gitleaks ──▶ Checkov
    │
    ▼
Build Docker Image
    │
    ▼
Trivy (Filesystem) ──▶ Trivy (Image) ──▶ Generate SBOM (Syft)
    │
    ▼
Docker Hub Login ──▶ Docker Hub Push ──▶ Sign Image (Cosign)
    │
    ▼
Kyverno Policy Validation (dry-run)
    │
    ▼
Deploy to Kubernetes (Helm)
    │
    ▼
Cleanup
```

### Détail des étapes

1. **Initialization** — récupère les paramètres transmis par le webhook (dépôt, branche).
2. **Checkout / Verify / Detect Project** — clone le dépôt applicatif et détecte automatiquement le langage et l'outil de build.
3. **Retrieve Secrets** — récupère les secrets nécessaires (`SONAR_TOKEN`, `NVD_API_KEY`, `COSIGN_PASSWORD`...) depuis HashiCorp Vault, sans jamais les stocker en dur.
4. **Build Application** — compile l'application.
5. **SonarQube Analysis** — analyse statique du code (SAST).
6. **OWASP Dependency-Check** — analyse des dépendances (SCA).
7. **Gitleaks** — détection de secrets dans le dépôt.
8. **Checkov** — analyse du Dockerfile et du Helm Chart (IaC). Non bloquant : les violations sont journalisées sans interrompre le pipeline.
9. **Build Docker Image** — construction d'une image multi-stage, publiée sous `saphae/myi-unicom-nova:${BUILD_NUMBER}`.
10. **Trivy** — analyse de vulnérabilités du filesystem puis de l'image Docker construite.
11. **Generate SBOM** — génération de la nomenclature logicielle (formats SPDX et CycloneDX) via Syft.
12. **Docker Hub Login / Push** — authentification et publication de l'image (tag de build + `latest`) via Jenkins Credentials.
13. **Sign Docker Image** — signature du digest de l'image avec Cosign ; le mot de passe de la clé privée est récupéré depuis Vault.
14. **Kyverno Policy Validation** — simulation du déploiement (`helm upgrade --dry-run=server`) pour évaluer la conformité aux politiques Kyverno avant tout déploiement réel.
15. **Deploy to Kubernetes** — connexion SSH à la VM K3s, exécution de `helm upgrade --install`, attente du rollout et vérification des ressources déployées.
16. **Cleanup** — nettoyage de l'espace de travail Jenkins.

Tous les rapports (HTML, JSON, XML) sont archivés automatiquement comme artefacts Jenkins.

## Déclenchement automatique du pipeline (Webhook + Smee)

Le pipeline se déclenche **automatiquement après chaque `git push`** (ou merge de Pull Request) sur le dépôt de l'application, sans aucune intervention manuelle. Comme Jenkins tourne en local sur la VM1 (non exposée publiquement), un relais est nécessaire pour que GitHub puisse atteindre Jenkins : **Smee.io**.

### Fonctionnement

```
Développeur                GitHub              smee.io              VM1 (Jenkins)
    │                         │                    │                      │
    │  git push / merge PR    │                    │                      │
    ├────────────────────────▶│                    │                      │
    │                         │  POST webhook      │                      │
    │                         ├───────────────────▶│                      │
    │                         │                    │  relais (smee-client)│
    │                         │                    ├─────────────────────▶│
    │                         │                    │                      │
    │                         │                    │   Generic Webhook    │
    │                         │                    │   Trigger (token)    │
    │                         │                    │          │           │
    │                         │                    │          ▼           │
    │                         │                    │   Pipeline démarré   │
```

1. Le développeur pousse une modification (ou merge une PR) sur le dépôt GitHub de l'application.
2. GitHub envoie un événement `POST` vers l'URL configurée dans le webhook.
3. Jenkins n'étant pas accessible depuis Internet, cette URL est un canal **Smee** (`https://smee.io/<id>`), qui reçoit la requête.
4. Le client `smee-client`, lancé sur la VM1, récupère cette requête et la retransmet en local vers Jenkins.
5. Jenkins reçoit la requête via le plugin **Generic Webhook Trigger**, qui vérifie le token de sécurité avant de déclencher le job.
6. Le pipeline s'exécute : le Jenkinsfile récupère automatiquement l'URL du dépôt et la branche concernée depuis le payload GitHub (`APP_REPOSITORY`, `APP_BRANCH`), puis clone et traite l'application correspondante.

### Installation de Smee (VM1)

```bash
node -v
npm -v
sudo npm install -g smee-client
smee --version
```

### Lancement du relais

```bash
smee \
  --url https://smee.io/<identifiant-du-canal> \
  --target "http://localhost:8080/generic-webhook-trigger/invoke?token=xxxxx"
```

> En production, ce relais Smee est remplacé par une exposition directe et sécurisée de Jenkins (voir [Mise en production](#mise-en-production--ce-qui-reste-à-durcir)).

### Configuration du job Jenkins

| Paramètre | Valeur |
|---|---|
| Definition | Pipeline script from SCM |
| SCM | Git |
| Repository URL | `https://github.com/safaesun/devsecops-platform.git` |
| Credentials | `github-pat` |
| Branch | `*/main` |
| Script Path | `jenkinsfiles/Jenkinsfile` |

### Configuration du Generic Webhook Trigger

| Variable | Expression | Type |
|---|---|---|
| `APP_REPOSITORY` | `$.repository.clone_url` | JSONPath |
| `APP_BRANCH` | `$.ref` | JSONPath |

Token de sécurité : `devsecops`
Options activées : *Print post content*, *Print contributed variables*

### Configuration du webhook côté dépôt applicatif (GitHub)

| Paramètre | Valeur |
|---|---|
| Dépôt concerné | `myi-unicom-nova-ai` |
| Payload URL | `https://smee.io/<identifiant-du-canal>` |
| Content-Type | `application/json` |
| Événements | *Just the push event* |

Un push/merge sur `main` déclenche ainsi le pipeline sans qu'aucun développeur n'ait besoin d'accéder à Jenkins directement.

## Jenkins Credentials

Les identifiants sensibles ne sont jamais stockés dans les scripts ni dans le dépôt : ils sont enregistrés dans **Jenkins Credentials** (portée *Global*) et référencés par leur identifiant (`credentialsId`) dans le Jenkinsfile.

| Credential ID | Type | Usage |
|---|---|---|
| `sonarqube-token` | Secret text | Authentification auprès de SonarQube pour l'analyse de code |
| `github-pat` | Username/Password | Personal Access Token GitHub, utilisé pour cloner les dépôts (plateforme et application) |
| `vault-token` | Secret text | Token racine utilisé par Jenkins pour s'authentifier auprès de Vault et récupérer les secrets |
| `dockerhub-credentials` | Username/Password | Authentification Docker Hub (login, push des images) |
| `cosign-private-key` | Secret file | Clé privée Cosign utilisée pour la signature des images Docker |
| `jenkins-token` | Secret text | Token de ServiceAccount K3s préparé pour un accès direct Jenkins → API Kubernetes *(non utilisé dans l'implémentation finale, voir ci-dessous)* |
| `k3s-ca-cert` | Secret file | Certificat CA de l'API K3s, préparé pour le même mécanisme *(non utilisé dans l'implémentation finale)* |
| `k3s-ssh` | SSH Username with private key | Clé SSH permettant à Jenkins de se connecter à la VM K3s pour exécuter Helm/kubectl |

> **Note** : `jenkins-token` et `k3s-ca-cert` correspondent à une première approche envisagée (un ServiceAccount Kubernetes dédié `jenkins-deployer`, avec accès direct à l'API Kubernetes). L'implémentation finale retenue repose sur une **connexion SSH** depuis Jenkins vers la VM K3s (credential `k3s-ssh`), Helm et kubectl étant ensuite exécutés directement sur la VM cible.

## Gestion des secrets avec Vault

### Passage du mode développement au mode fichier persistant

Lors de la mise en place initiale, Vault tournait en **mode `-dev`** :

```yaml
command: vault server -dev
environment:
  VAULT_DEV_ROOT_TOKEN_ID: xxxxxx
  VAULT_DEV_LISTEN_ADDRESS: "0.0.0.0:8200"
```

**Problème rencontré** : en mode `-dev`, Vault ignore tout stockage persistant — même avec un volume monté, les données restent uniquement en mémoire. Résultat : tous les secrets étaient perdus à chaque redémarrage du conteneur.

**Correction** : bascule vers un stockage de type `file`, avec une configuration explicite (`vault.hcl`) :

```hcl
storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr     = "http://0.0.0.0:8200"
ui           = true
disable_mlock = true
```

```yaml
services:
  vault:
    image: hashicorp/vault:1.20
    container_name: vault
    restart: unless-stopped
    cap_add:
      - IPC_LOCK
    ports:
      - "8200:8200"
    volumes:
      - /home/saphae/devsecops/data/vault:/vault/file
      - ./config:/vault/config
    command: vault server -config=/vault/config/vault.hcl
    networks:
      - devsecops-network
```

> `tls_disable = 1` reste acceptable en environnement de développement local (VM isolée). Ce paramètre doit être revu avant toute mise en production (voir [Mise en production](#mise-en-production--ce-qui-reste-à-durcir)).

### Initialisation et déverrouillage (unseal)

```bash
docker compose -f docker-compose-dev.yml down
docker compose up -d

export VAULT_ADDR=http://127.0.0.1:8200
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -it vault vault operator init
```

Vault génère 5 **Unseal Keys** et un **Initial Root Token**, à conserver en lieu sûr — ils ne sont affichés qu'une seule fois. Contrairement au mode `-dev`, ce mode nécessite un déverrouillage (*unseal*) après chaque redémarrage du conteneur, via `vault operator unseal`.

```bash
export VAULT_ADDR=http://192.168.56.109:8200
vault login
```

### Secrets stockés

```bash
vault secrets list   # confirme la présence du moteur KV (secret/)

vault kv put secret/devsecops/sonar    token="..."
vault kv put secret/devsecops/github   token="..."
vault kv put secret/devsecops/registry username="..." password="..."
vault kv put secret/devsecops/cosign   password="..."
vault kv patch secret/devsecops/cosign private_key="$(cat cosign.key)"
vault kv patch secret/devsecops/cosign public_key="$(cat cosign.pub)"
```

Le script `scripts/retrieve-secrets.sh` centralise la récupération de ces secrets pendant le pipeline, en appliquant le principe du moindre privilège : chaque étape ne récupère que le secret dont elle a strictement besoin (Sonar ne récupère que `sonar/token`, Cosign que `cosign/password` et `cosign/private_key`, etc.).

## Base de données de l'application (Laravel/Laragon)

La base de données de l'application **n'est pas hébergée dans le cluster K3s** : elle tourne sur la machine physique hôte (Windows), via **Laragon** (MySQL + phpMyAdmin), et reste accessible depuis les deux VM grâce au réseau privé partagé `192.168.56.1`.

```
Machine physique (Windows + Laragon)
        192.168.56.1:3306
        ├── unicomnova            (utilisateurs, authentification)
        └── unicomnova_centrale   (produits, prix, données du chatbot)
                 ▲
                 │ MySQL 3306
                 │
        VM2 — K3s (192.168.56.112)
        Pod application (Laravel)
```

### Création de l'utilisateur applicatif via phpMyAdmin (Laragon)

1. Démarrer Laragon et ouvrir phpMyAdmin (`http://localhost/phpmyadmin` sur la machine hôte).
2. Créer les deux bases si elles n'existent pas encore : `unicomnova` et `unicomnova_centrale`.
3. Dans l'onglet **Comptes utilisateurs**, créer un utilisateur dédié à l'application (ex. `unicom_app`), avec :
   - **Hôte** : `%` (ou l'IP du réseau VirtualBox `192.168.56.%`) — pas `localhost`, car les connexions proviennent des VM.
   - **Mot de passe** : à définir, stocké ensuite dans le Secret Kubernetes `unicomnova-env` (jamais en clair dans les manifests).
4. Accorder les privilèges nécessaires sur les deux bases (`unicomnova` et `unicomnova_centrale`) à cet utilisateur.
5. Vérifier que MySQL écoute bien sur toutes les interfaces (`bind-address = 0.0.0.0` dans la config Laragon/MySQL), pas seulement `127.0.0.1`, sinon les VM ne pourront pas s'y connecter.

### Vérification de la connectivité depuis K3s

```bash
nc -zv 192.168.56.1 3306
```

### Variables d'environnement Laravel correspondantes

```
DB_CONNECTION=mysql
DB_HOST=192.168.56.1
DB_PORT=3306
DB_DATABASE=unicomnova
DB_USERNAME=unicom_app
DB_PASSWORD=...

UNICOM_DB_CONNECTION=mysql
UNICOM_DB_HOST=192.168.56.1
UNICOM_DB_PORT=3306
UNICOM_DB_DATABASE=unicomnova_centrale
UNICOM_DB_USERNAME=unicom_app
UNICOM_DB_PASSWORD=...
```


Ces variables sont injectées dans le Pod via le Secret Kubernetes `unicomnova-env` (voir [Sécurité du déploiement Kubernetes](#sécurité-du-déploiement-kubernetes)), jamais écrites en dur dans le code ni dans l'image Docker.

## Structure du dépôt

```
devsecops-platform/
├── jenkinsfiles/
│   └── Jenkinsfile
├── scripts/
│   ├── detect-project.sh
│   ├── retrieve-secrets.sh
│   ├── build.sh
│   ├── sonarqube.sh
│   ├── dependency-check.sh
│   ├── gitleaks.sh
│   ├── checkov.sh
│   ├── build-image.sh
│   ├── trivy.sh
│   ├── trivy-image.sh
│   ├── syft.sh
│   ├── docker-login.sh
│   ├── docker-push.sh
│   ├── cosign.sh
│   ├── kyverno.sh
│   ├── deploy.sh
│   └── cleanup.sh
├── dockerfiles/
│   └── jenkins/
│       └── Dockerfile          # image Jenkins personnalisée (voir ci-dessous)
├── compose/
│   ├── jenkins/
│   │   └── docker-compose.yml
│   ├── sonarqube/
│   │   └── docker-compose.yml  # SonarQube + PostgreSQL
│   └── vault/
│       ├── docker-compose.yml
│       └── config/
└── kubernetes/
    ├── charts/
    │   └── application/         # Helm Chart générique de l'application
    │       ├── Chart.yaml
    │       ├── values.yaml
    │       └── templates/
    │           ├── deployment.yaml
    │           ├── service.yaml
    │           ├── nginx-configmap.yaml
    │           └── ingressroute.yaml
    ├── kyverno/
    │   └── policies/
    │       └── security-baseline.yaml
    └── monitoring/
        ├── values-kube-prometheus-stack.yaml
        ├── grafana-ingressroute.yaml
        ├── loki/
        │   └── values-loki.yaml
        └── promtail/
            └── values-promtail.yaml
```

### Image Jenkins personnalisée

Jenkins tourne dans une image construite sur-mesure (`dockerfiles/jenkins/Dockerfile`), embarquant tous les outils nécessaires au pipeline : Docker CLI, Vault CLI, kubectl, Helm, Trivy, Syft, Cosign, Gitleaks, Sonar Scanner, OWASP Dependency-Check, Checkov, ainsi que PHP-CLI et Composer pour l'application Laravel.

### Chart Helm générique

Le chart `kubernetes/charts/application/` est volontairement générique : aucune valeur n'est codée en dur (image, host, ressources), tout est injecté au moment du déploiement via `--set`. Le déploiement crée un seul Pod avec deux conteneurs partageant le même réseau :

- **application** — PHP-FPM (Laravel), écoute sur le port 9000
- **nginx** — serveur web, écoute sur le port 80, transmet les requêtes PHP à `127.0.0.1:9000`

Un `initContainer` (`copy-application`) copie le code applicatif vers un volume partagé (`emptyDir`), accessible en lecture par le conteneur Nginx. La base de données (MySQL) est externe au cluster, hébergée hors K3s.

## Sécurité du déploiement Kubernetes

Au-delà de l'analyse statique réalisée par Checkov, plusieurs mécanismes de sécurité et de fiabilité ont été appliqués directement au niveau du Helm Chart :

- **Readiness / Liveness Probes** — vérification de la disponibilité du Pod avant de router du trafic, et redémarrage automatique en cas de défaillance.
- **Requests / Limits CPU et mémoire** — définis pour les deux conteneurs, évitant toute consommation illimitée de ressources sur le nœud.
- **SecurityContext durci** :
  - `runAsNonRoot: true` au niveau Pod
  - `runAsUser` / `runAsGroup: 82` (utilisateur non privilégié)
  - `allowPrivilegeEscalation: false`
  - `readOnlyRootFilesystem: true`
  - `seccompProfile: RuntimeDefault`
  - capacités Linux réduites au strict nécessaire (`drop: ALL`, ajout uniquement de `NET_BIND_SERVICE`, `CHOWN`, `SETUID`, `SETGID` pour Nginx)
- **Volumes `emptyDir`** pour les répertoires nécessitant l'écriture malgré le filesystem racine en lecture seule (`/tmp`, `/var/cache/nginx`, `/var/run`).
- **Secrets Kubernetes** — les variables sensibles de l'application (`APP_KEY`, connexions base de données) sont injectées via `envFrom.secretRef`, jamais écrites dans l'image ni dans les manifests.

Chaque durcissement a été validé progressivement (`helm lint` → `helm template` → `helm upgrade` → `kubectl describe pod`) pour éviter de casser un déploiement fonctionnel.

## Kyverno — Policy Engine

Kyverno est installé sur la VM Kubernetes comme **Admission Controller**, indépendamment du pipeline Jenkins — il intercepte en permanence toute création ou modification de ressource sur le cluster.

Une `ClusterPolicy` unique, `security-baseline`, regroupe quatre règles reprenant le durcissement déjà appliqué manuellement dans le chart :

- exécution non-root (`runAsNonRoot`)
- limites de ressources CPU/mémoire obligatoires
- interdiction de l'élévation de privilèges
- système de fichiers racine en lecture seule

La policy est actuellement en mode **`Audit`** (journalisation des violations sans blocage), le temps de valider la conformité de la plateforme avant de basculer en `Enforce`.

Dans le pipeline, le stage **Kyverno Policy Validation** simule le déploiement (`helm upgrade --dry-run=server`) avant le déploiement réel, ce qui permet à Kyverno d'évaluer la conformité sans jamais créer de ressource sur le cluster.

## Monitoring et observabilité

La supervision repose sur le chart communautaire `kube-prometheus-stack` (Prometheus, Grafana, Alertmanager, Node Exporter, kube-state-metrics), complété par Loki et Promtail pour la centralisation des journaux.

- **Grafana** est exposée via une `IngressRoute` Traefik, au même titre que l'application métier.
- **Promtail**, retiré du chart Loki à partir de sa version 7, a été installé comme chart Helm indépendant, configuré pour découvrir automatiquement tous les pods du cluster via l'API Kubernetes.
- Un dashboard communautaire (Loki Stack Monitoring) a été importé dans Grafana pour la visualisation des journaux.

Tous les composants disposent de ressources CPU/mémoire explicitement définies, après plusieurs incidents de démarrage (`OOMKilled`, `CrashLoopBackOff`) diagnostiqués et corrigés en cours de mise en place.

## Persistance des données

Les composants critiques utilisent des volumes persistants (`PersistentVolumeClaim`, StorageClass `local-path`) afin de conserver leurs données malgré le redémarrage des Pods :

| Composant | Volume |
|---|---|
| Prometheus | 5 Gi (rétention 5 jours) |
| Grafana | 2 Gi |
| Alertmanager | 1 Gi |
| Loki | 5 Gi (rétention 72h) |
| Jenkins | volume hôte (`/home/saphae/devsecops/data/jenkins`) |
| SonarQube / PostgreSQL | volume hôte |
| Vault | volume hôte |

Ce mécanisme protège contre la suppression/recréation d'un Pod, mais pas contre la perte complète de la VM — cohérent avec un environnement de développement/démonstration sur cluster single-node.

# Installation

Cette section reprend, **dans l'ordre exact où elles ont été réalisées**, l'intégralité des étapes ayant permis de construire cette plateforme — depuis la préparation des deux machines jusqu'au premier déploiement automatisé de l'application. Chaque étape indique la machine concernée (**VM1 — DevSecOps** ou **VM2 — Kubernetes**) et, quand nécessaire, une remarque pour l'adapter à un serveur d'entreprise (VPS).

> **Remarque générale pour un déploiement VPS** : remplacez systématiquement les adresses IP privées (`192.168.56.109`, `192.168.56.112`) par l'IP publique/privée ou le nom de domaine réel de vos serveurs. En production, Jenkins, SonarQube et Vault doivent être placés derrière un reverse proxy HTTPS plutôt qu'exposés directement sur leurs ports (voir [Mise en production](#mise-en-production--ce-qui-reste-à-durcir)).

---

### Phase 1 — Préparation des deux machines (VM1 et VM2)

```bash
# Sur les deux machines
sudo apt update
sudo apt install openssh-server -y
sudo systemctl enable ssh
sudo systemctl start ssh
systemctl status ssh

sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

sudo apt install -y \
  curl wget git vim nano tree unzip zip htop jq \
  net-tools software-properties-common apt-transport-https \
  ca-certificates gnupg lsb-release dnsutils

# Désactiver le swap (recommandé pour Kubernetes)
sudo swapoff -a

# Vérifier les adresses IP
ip a
```

Vérifier la connectivité entre les deux machines :
```bash
ping <IP_VM2>   # depuis VM1
ping <IP_VM1>   # depuis VM2
```

> **Remarque VPS** : sur un VPS, cette connectivité passe généralement par un réseau privé fourni par l'hébergeur plutôt qu'un réseau NAT local — ouvrez dans le firewall les ports nécessaires entre les deux instances (8080, 8200, 9000, 6443, 22).

---

### Phase 2 — Installation de Docker (VM1)

```bash
sudo apt remove docker docker.io containerd runc -y

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER
newgrp docker

docker run hello-world

sudo systemctl enable docker
sudo systemctl start docker
systemctl status docker
docker compose version
```

---

### Phase 3 — Arborescence du projet

**Sur VM1** :
```bash
mkdir -p ~/devsecops-platform
cd ~/devsecops-platform

mkdir -p compose data jenkinsfiles dockerfiles scripts config certs backups reports
mkdir -p compose/jenkins compose/sonarqube compose/vault
mkdir -p data/jenkins data/sonarqube data/vault data/postgresql
```

**Sur VM2** :
```bash
mkdir -p ~/devsecops-platform/kubernetes/{charts,monitoring,kyverno}
```

> **Remarque VPS** : en production, préférez cloner directement le dépôt Git de la plateforme (`git clone https://github.com/safaesun/devsecops-platform.git`) plutôt que de recréer chaque dossier à la main — tous les fichiers `docker-compose.yml`, le `Dockerfile` Jenkins et les charts Kubernetes sont déjà versionnés.

---

### Phase 4 — Réseau Docker partagé (VM1)

```bash
docker network create devsecops-network
docker network ls   # devsecops-network doit apparaître
```

Ce réseau permet à Jenkins, SonarQube, PostgreSQL et Vault de communiquer entre eux par nom de conteneur.

---

### Phase 5 — Jenkins  : image personnalisée et démarrage + tools (VM1)

Le `Dockerfile` (`dockerfiles/jenkins/Dockerfile`) embarque tous les outils nécessaires au pipeline (Docker CLI, Vault CLI, kubectl, Helm, Trivy, Syft, Cosign, Gitleaks, Sonar Scanner, OWASP Dependency-Check, Checkov, PHP-CLI, Composer) — voir [Versions des outils](#versions-des-outils).

```bash
cd ~/devsecops-platform/dockerfiles/jenkins
docker build -t devsecops-jenkins:lts .
```

Créer `compose/jenkins/docker-compose.yml` :
```yaml
services:
  jenkins:
    build:
      context: ../../
      dockerfile: dockerfiles/jenkins/Dockerfile
    image: devsecops-jenkins:lts
    container_name: jenkins
    restart: unless-stopped
    user: root
    privileged: true
    ports:
      - "8080:8080"
      - "50000:50000"
    environment:
      TZ: Africa/Casablanca
    volumes:
      - /home/saphae/devsecops/data/jenkins:/var/jenkins_home
      - /home/saphae/devsecops/data/dependency-check:/var/jenkins_home/odc-data
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - devsecops-network
networks:
  devsecops-network:
    external: true
```

```bash
cd ~/devsecops-platform/compose/jenkins
cat docker-compose.yml
docker compose config      # vérifie la syntaxe, aucune erreur ne doit apparaître
docker compose up -d

docker ps                  # le conteneur "jenkins" doit apparaître
docker logs -f jenkins     # attendre le message de démarrage complet, puis Ctrl+C

docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Accéder à `http://<IP_VM1>:8080`, saisir le mot de passe initial, choisir **Install suggested plugins**, puis créer le compte administrateur (Username, Full Name, Email, mot de passe) et conserver l'URL Jenkins.

**Plugins complémentaires à installer** (*Manage Jenkins → Plugins → Available plugins*) :

- Git, GitHub
- Pipeline, Pipeline Utility Steps
- Docker, Docker Pipeline
- Credentials Binding, SSH Agent
- SonarQube Scanner
- Kubernetes CLI
- Workspace Cleanup, AnsiColor, Timestamper
- Email Extension
- Generic Webhook Trigger
- HashiCorp Vault Plugin

> **Remarque VPS** : ne jamais exposer directement le port `8080` sur Internet — placez un reverse proxy HTTPS (Nginx, Traefik) en frontal, et restreignez l'accès à ce port au réseau interne/VPN.

---
##  Installer les outils de sécurité sur VM1

### Gitleaks

```bash
mkdir -p ~/devsecops/tools
cd ~/devsecops/tools
wget https://github.com/gitleaks/gitleaks/releases/download/v8.28.0/gitleaks_8.28.0_linux_x64.tar.gz
tar -xzf gitleaks_8.28.0_linux_x64.tar.gz
sudo mv gitleaks /usr/local/bin/
sudo chmod +x /usr/local/bin/gitleaks
gitleaks version
```

### OWASP Dependency-Check

```bash
mkdir -p ~/devsecops/tools
cd ~/devsecops/tools
wget https://github.com/dependency-check/DependencyCheck/releases/download/v12.1.0/dependency-check-12.1.0-release.zip
unzip dependency-check-12.1.0-release.zip
chmod +x dependency-check/bin/dependency-check.sh
sudo ln -sf ~/devsecops/tools/dependency-check/bin/dependency-check.sh /usr/local/bin/dependency-check
```

Installer Java :

```bash
sudo apt update
sudo apt install openjdk-21-jdk -y
```

Configurer `JAVA_HOME` dans `~/.bashrc`.

Vérifier :

```bash
java -version
dependency-check --version
```

### Checkov

Sous Ubuntu, utiliser `pipx` :

```bash
sudo apt install pipx -y
pipx ensurepath
source ~/.bashrc
pipx install checkov
checkov --version
which checkov
```

Le projet a utilisé Checkov pour les Dockerfiles et les Helm Charts Kubernetes.

### Trivy

Installer via le dépôt officiel Aquasecurity :

```bash
sudo apt update
sudo apt install wget gnupg lsb-release apt-transport-https -y
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update
sudo apt install trivy -y
trivy --version
```

### Syft

```bash
cd ~/devsecops/tools
wget https://github.com/anchore/syft/releases/download/v1.34.2/syft_1.34.2_linux_amd64.tar.gz
tar -xzf syft_1.34.2_linux_amd64.tar.gz
sudo mv syft /usr/local/bin/
sudo chmod +x /usr/local/bin/syft
syft version
```

### Cosign

```bash
cd ~/devsecops/tools
wget https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
cosign version
```




### Phase 6 — SonarQube + PostgreSQL (VM1)

```bash
mkdir -p ~/devsecops-platform/data/postgresql
mkdir -p ~/devsecops-platform/data/sonarqube/{data,extensions,logs}
```

Créer `compose/sonarqube/docker-compose.yml` :
```yaml
services:
  postgresql:
    image: postgres:16
    container_name: postgresql
    restart: unless-stopped
    environment:
      POSTGRES_DB: sonarqube
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: SonarStrongPassword123
      TZ: Africa/Casablanca
    ports:
      - "5432:5432"
    volumes:
      - /home/saphae/devsecops/data/postgresql:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonar -d sonarqube"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - devsecops-network
  sonarqube:
    image: sonarqube:lts-community
    container_name: sonarqube
    restart: unless-stopped
    depends_on:
      postgresql:
        condition: service_healthy
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://postgresql:5432/sonarqube
      SONAR_JDBC_USERNAME: xxxxx
      SONAR_JDBC_PASSWORD: xxxxx
      TZ: Africa/Casablanca
    ports:
      - "9000:9000"
    volumes:
      - /home/saphae/devsecops/data/sonarqube/data:/opt/sonarqube/data
      - /home/saphae/devsecops/data/sonarqube/extensions:/opt/sonarqube/extensions
      - /home/saphae/devsecops/data/sonarqube/logs:/opt/sonarqube/logs
    networks:
      - devsecops-network
networks:
  devsecops-network:
    external: true
```

```bash
cd ~/devsecops-platform/compose/sonarqube
docker compose config
docker compose up -d

docker ps
docker logs -f sonarqube   # attendre le message de démarrage complet
```

Accéder à `http://<IP_VM1>:9000` (identifiants par défaut `admin` / `admin`, changement de mot de passe demandé au premier accès).

> **Remarque VPS** : le port `5432` (PostgreSQL) ne doit **jamais** être exposé sur Internet — retirez le mapping de port public ou restreignez-le au réseau interne uniquement.

---

### Phase 7 — Intégration Jenkins ↔ SonarQube (VM1)

1. Dans SonarQube : **My Account → Security → Tokens** → générer un token (*Name* : `jenkins-global-analysis`, *Type* : `Global Analysis Token`).
2. Dans Jenkins : *Manage Jenkins → System → SonarQube servers → Add SonarQube* :
   - **Name** : `SonarQube`
   - **Server URL** : `http://<IP_VM1>:9000`
   - **Server authentication token** → *Add → Jenkins* :
     - **Kind** : `Secret text`
     - **Scope** : `Global`
     - **Secret** : le token généré
     - **ID** : `sonarqube-token`
     - **Description** : `SonarQube Authentication Token`
   - Sélectionner `sonarqube-token`, cocher **Environment variables**, puis **Save**.
3. *Manage Jenkins → Tools → SonarQube Scanner → Add SonarQube Scanner* :
   - **Name** : `SonarScanner`
   - Cocher **Install automatically**
   - **Save**

---

### Phase 8 — Vault : gestion centralisée des secrets (VM1)

> ⚠️ **Piège rencontré durant le projet, à éviter directement en production** : Vault a d'abord été lancé en **mode `-dev`** (`vault server -dev`). En mode `-dev`, Vault **ignore tout stockage persistant**, même avec un volume monté — les secrets ne sont conservés qu'en mémoire et disparaissent au moindre redémarrage du conteneur. **Installez directement le mode `file` ci-dessous.**

Créer `compose/vault/config/vault.hcl` :
```hcl
storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr      = "http://0.0.0.0:8200"
ui            = true
disable_mlock = true
```

Créer `compose/vault/docker-compose.yml` :
```yaml
services:
  vault:
    image: hashicorp/vault:1.20
    container_name: vault
    restart: unless-stopped
    cap_add:
      - IPC_LOCK
    ports:
      - "8200:8200"
    volumes:
      - /home/saphae/devsecops/data/vault:/vault/file
      - ./config:/vault/config
    command: vault server -config=/vault/config/vault.hcl
    networks:
      - devsecops-network
networks:
  devsecops-network:
    external: true
```

```bash
mkdir -p ~/devsecops-platform/data/vault
cd ~/devsecops-platform/compose/vault
docker compose up -d

docker ps
docker logs -f vault

export VAULT_ADDR=http://127.0.0.1:8200
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -it vault vault operator init
```

Vault génère **5 Unseal Keys** et un **Initial Root Token** — à conserver précieusement, ils ne sont affichés qu'une seule fois.

```bash
# Déverrouiller Vault (à répéter avec 3 clés différentes parmi les 5)
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -it vault vault operator unseal
```

Ouvrir l'interface : `http://<IP_VM1>:8200`, se connecter avec le Root Token.

#### Configuration du client Vault CLI (VM1)

```bash
cd ~/devsecops-platform/tools   # ou tout dossier de travail

wget https://releases.hashicorp.com/vault/1.20.4/vault_1.20.4_linux_amd64.zip
unzip vault_1.20.4_linux_amd64.zip
sudo mv vault /usr/local/bin/
sudo chmod +x /usr/local/bin/vault

echo 'export VAULT_ADDR=http://127.0.0.1:8200' >> ~/.bashrc
source ~/.bashrc
echo $VAULT_ADDR

vault login   # coller le Root Token
vault secrets list   # confirme la présence du moteur KV (secret/)
```

#### Création des secrets utilisés par le pipeline

```bash
# GitHub (pour cloner les dépôts applicatifs si nécessaire depuis Vault)
vault kv put secret/devsecops/github \
  username="<votre-compte-github>" \
  token="<VOTRE_GITHUB_PAT>"

# SonarQube
vault kv put secret/devsecops/sonar \
  token="<TOKEN_SONARQUBE>" \
  SONAR_HOST_URL="http://sonarqube:9000"

# Registre d'images (Docker Hub, ou Nexus si retenu — voir Phase 14)
vault kv put secret/devsecops/registry \
  username="<USER_DOCKERHUB>" \
  password="<PASSWORD_DOCKERHUB>"
```

**Génération et stockage de la paire de clés Cosign** :
```bash
cosign generate-key-pair
# Vault demande un mot de passe pour protéger la clé privée

ls -l cosign.*   # cosign.key (privée) et cosign.pub (publique)

mkdir -p ~/devsecops-platform/certs/cosign
mv cosign.key cosign.pub ~/devsecops-platform/certs/cosign/

vault kv put secret/devsecops/cosign \
  password="<MOT_DE_PASSE_CLE_COSIGN>"
vault kv patch secret/devsecops/cosign \
  private_key=@~/devsecops-platform/certs/cosign/cosign.key
vault kv patch secret/devsecops/cosign \
  public_key="$(cat ~/devsecops-platform/certs/cosign/cosign.pub)"
```

Vérifier chaque secret :
```bash
vault kv get secret/devsecops/github
vault kv get secret/devsecops/sonar
vault kv get secret/devsecops/registry
vault kv get secret/devsecops/cosign
```

#### Intégration Jenkins ↔ Vault

1. *Manage Jenkins → Plugins → Available* → installer **HashiCorp Vault Plugin**.
2. *Manage Jenkins → System → HashiCorp Vault → Add Vault Configuration* :
   - **Vault URL** : `http://vault:8200` (nom du conteneur, Jenkins et Vault partageant `devsecops-network`)
   - **Engine Version** : `2`
3. *Add Credentials* :
   - **Type** : `Vault Token Credential`
   - **Nom** : `Vault Root Token` (ID : `vault-token`)
   - **Token** : le Root Token généré précédemment
4. Associer ce credential à la configuration Vault, puis **Save**.

**Test rapide** (job Jenkins temporaire, optionnel) :
```groovy
pipeline {
    agent any
    environment {
        REGISTRY_USER = vault path: 'secret/devsecops/registry', key: 'username'
    }
    stages {
        stage('Test Vault') {
            steps {
                sh 'echo "Utilisateur récupéré depuis Vault avec succès."'
            }
        }
    }
}
```

> **Remarque VPS — sécurité renforcée à prévoir** : ce mode reste minimal (`tls_disable = 1`, root token unique utilisé partout). En production, activez un listener TLS avec un certificat réel, remplacez l'usage direct du root token par des **policies Vault** dédiées par service (principe du moindre privilège — Sonar ne doit pouvoir lire que `secret/devsecops/sonar`, etc.), et envisagez l'auto-unseal via un KMS cloud plutôt qu'un unseal manuel après chaque redémarrage.

---

### Phase 9 — Dépôt Git de la plateforme (VM1)

```bash
cd ~/devsecops-platform

git init
git branch -M main
git remote add origin https://github.com/<votre-compte>/devsecops-platform.git
git remote -v

git config --global user.name "<votre-nom>"
git config --global user.email "<votre-email>"
```

Créer `.gitignore` :
```
############################
# Docker volumes
############################
data/

############################
# Installed tools (VM only)
############################
tools/

############################
# Generated reports
############################
reports/*.html
reports/*.json
reports/*.xml
reports/*.csv

############################
# Cosign keys
############################
*.key
*.pub

############################
# Tool caches
############################
.trivy/
.dependency-check/

############################
# Logs
############################
*.log

############################
# Temporary files
############################
*.tmp
*.bak
*.swp
*~

############################
# Python
############################
__pycache__/
*.pyc

############################
# IDE
############################
.vscode/
.idea/

############################
# Operating System
############################
.DS_Store
Thumbs.db
```

```bash
git add .
git rm -r --cached tools   # si le dossier tools avait déjà été suivi
git add .gitignore
git status
git commit -m "Initial DevSecOps platform structure"
git log --oneline

git config --global credential.helper store
git push -u origin main
```

> **Point rencontré durant le projet** : ` — GitHub n'accepte plus l'authentification par mot de passe simple. **Solution** : créer un **Personal Access Token (PAT)** — *GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token (classic)*, avec la permission `repo — puis réutiliser ce token comme mot de passe lors du push (Username : votre compte GitHub, Password : le PAT).

---

### Phase 10 — Création du Job Pipeline Jenkins (VM1)

1. Dans Jenkins : **New Item** → Nom : `DevSecOps-Pipeline` → Type : `Pipeline` → **OK**.
2. **General** : laisser les options par défaut.
3. **Build Triggers** : ne rien cocher pour l'instant (le webhook sera configuré une fois le pipeline fonctionnel — voir [Déclenchement automatique du pipeline](#déclenchement-automatique-du-pipeline-webhook--smee)).
4. **Pipeline** :
   - **Definition** : `Pipeline script from SCM`
   - **SCM** : `Git`
   - **Repository URL** : `https://github.com/<votre-compte>/devsecops-platform.git`
   - **Credentials** → *Add → Jenkins* :
     - **Username** : votre compte GitHub
     - **Password** : le Personal Access Token GitHub
     - **ID** : `github-pat`
     - **Description** : `GitHub Personal Access Token`
   - **Branches to build** : `*/main`
   - **Script Path** : `jenkinsfiles/Jenkinsfile` *(exactement cette valeur — ni `Jenkinsfile` seul, ni `./jenkinsfiles/Jenkinsfile`)*
5. **Save**, puis **Build Now** pour un premier test.

---

### Phase 11 — Rendre le pipeline générique (paramétrage)

Objectif : ne plus coder l'URL du dépôt applicatif en dur, pour que la même plateforme puisse construire n'importe quelle application en changeant uniquement un paramètre.

```bash
cd ~/devsecops-platform
touch jenkinsfiles/Jenkinsfile
nano jenkinsfiles/Jenkinsfile
```

```groovy
pipeline {

    agent any

    parameters {

        string(
            name: 'APP_REPOSITORY',
            defaultValue: '',
            description: 'Git repository URL of the application'
        )

        string(
            name: 'APP_BRANCH',
            defaultValue: 'main',
            description: 'Git branch of the application'
        )

    }

    stages {

        stage('Initialization') {

            steps {

                script {

                    if (!params.APP_REPOSITORY?.trim()) {
                        error("APP_REPOSITORY was not received from the webhook.")
                    }

                    if (!params.APP_BRANCH?.trim()) {
                        error("APP_BRANCH was not received from the webhook.")
                    }

                    env.APP_REPOSITORY = params.APP_REPOSITORY

                    env.APP_BRANCH = params.APP_BRANCH.replace("refs/heads/", "")

                }

                echo '======================================='
                echo ' DevSecOps Platform Pipeline Started'
                echo '======================================='

                echo "Application Repository : ${env.APP_REPOSITORY}"
                echo "Application Branch     : ${env.APP_BRANCH}"

            }

        }

git add jenkinsfiles/Jenkinsfile
git commit -m "Add application repository parameters"
git push
```

À partir de cette étape, n'importe quelle application peut être construite, sans modifier le pipeline.

---

### Phase 12 — Script de détection automatique du langage (VM1)

```bash
cd ~/devsecops-platform
touch scripts/detect-project.sh
chmod +x scripts/detect-project.sh
nano scripts/detect-project.sh
```

```bash
#!/bin/bash
set -e

LANGUAGE="unknown"
BUILD_TOOL="unknown"

if [ -f "composer.json" ]; then
    LANGUAGE="php"; BUILD_TOOL="composer"
elif [ -f "pom.xml" ]; then
    LANGUAGE="java"; BUILD_TOOL="maven"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    LANGUAGE="java"; BUILD_TOOL="gradle"
elif [ -f "package.json" ]; then
    LANGUAGE="node"; BUILD_TOOL="npm"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    LANGUAGE="python"; BUILD_TOOL="pip"
elif [ -f "go.mod" ]; then
    LANGUAGE="go"; BUILD_TOOL="go"
elif ls *.csproj >/dev/null 2>&1; then
    LANGUAGE="dotnet"; BUILD_TOOL="dotnet"
elif [ -f "Cargo.toml" ]; then
    LANGUAGE="rust"; BUILD_TOOL="cargo"
elif [ -f "Gemfile" ]; then
    LANGUAGE="ruby"; BUILD_TOOL="bundler"
elif [ -f "Dockerfile" ]; then
    LANGUAGE="generic"; BUILD_TOOL="docker"
else
    echo "Unsupported project."
    exit 1
fi

echo "LANGUAGE=${LANGUAGE}"
echo "BUILD_TOOL=${BUILD_TOOL}"
```

```bash
git add scripts/detect-project.sh
git commit -m "Add project detection script"
git push
```

Ajouter ensuite le `stage('Detect Project')` correspondant dans le Jenkinsfile (voir [Pipeline CI/CD](#pipeline-cicd) pour le stage complet), committer et pousser.

---

### Phase 13 — Récupération des secrets Vault dans le pipeline (VM1)

Créer `scripts/retrieve-secrets.sh`, qui interroge Vault avec le token Jenkins et exporte uniquement les secrets nécessaires (`GITHUB_TOKEN`, `SONAR_TOKEN`, `SONAR_HOST_URL`, `NVD_API_KEY`, `COSIGN_PASSWORD`...). Ajouter le `stage('Retrieve Secrets')` correspondant, protégé par `withCredentials([...])` pour ne jamais exposer le token Vault dans les journaux Jenkins.

```bash
git add scripts/retrieve-secrets.sh jenkinsfiles/Jenkinsfile
git commit -m "Add Vault secrets retrieval stage"
git push
```

> Ce principe est appliqué à chaque étape suivante : chaque stage ne récupère que le secret dont il a strictement besoin (Sonar ne lit que `sonar/token`, Cosign que `cosign/password` et `cosign/private_key`), conformément au principe du moindre privilège.

---

### Phase 14 — Build, SonarQube, Dependency-Check, Gitleaks, Checkov (VM1)

Ajouter successivement, en committant/poussant après chaque ajout :

1. **`stage('Build Application')`** → `scripts/build.sh` (ex. `composer install --no-interaction --prefer-dist` pour une application PHP/Laravel).
2. **`stage('SonarQube Analysis')`** → `scripts/sonarqube.sh`, en s'appuyant sur `SONAR_TOKEN`/`SONAR_HOST_URL` récupérés depuis Vault.
3. **`stage('OWASP Dependency Check')`** → `scripts/dependency-check.sh`, utilisant la clé API NVD stockée dans Vault.
4. **`stage('Gitleaks Secret Scan')`** → `scripts/gitleaks.sh`.
5. **`stage('Checkov IaC Scan')`** → `scripts/checkov.sh`, non bloquant par choix (voir [Sécurité du déploiement Kubernetes](#sécurité-du-déploiement-kubernetes)).

À chaque merge/push sur `main`, le pipeline s'exécute automatiquement une fois le webhook configuré (voir Phase 22) : clonage → détection du langage → récupération des secrets → build → analyses de qualité et de sécurité, sans qu'aucun token ne transite en clair dans le code, le Jenkinsfile ou GitHub.

> Tous les outils utilisés ici (Gitleaks, OWASP Dependency-Check, Checkov, Sonar Scanner) ont d'abord été **validés individuellement en ligne de commande sur VM1**, avant d'être intégrés dans l'image Jenkins personnalisée (`dockerfiles/jenkins/Dockerfile`) — cette double validation (test manuel puis intégration) fait partie de la démarche du projet, mais **n'est pas nécessaire à reproduire en production** : l'image Jenkins construite en Phase 5 contient déjà tous ces outils prêts à l'emploi.

---

### Phase 15 — Registre d'images : Docker Hub (VM1)

Créer le credential Jenkins `dockerhub-credentials` (*Username/Password*), puis ajouter les stages `Build Docker Image`, `Trivy Filesystem Scan`, `Trivy Docker Image Scan`, `Generate SBOM`, `Docker Hub Login`, `Docker Hub Push`, `Sign Docker Image` (voir [Pipeline CI/CD](#pipeline-cicd) pour le détail de chaque script).

> **Alternative — registre privé auto-hébergé (Nexus)** : le projet a initialement mis en place **Nexus Repository** (dépôts Docker Hosted et Proxy, groupe Docker, authentification testée avec succès), avant de basculer vers Docker Hub pour simplifier l'intégration. Si l'entreprise a besoin d'un registre privé pour des raisons de conformité, Nexus reste une alternative validée : réintroduire un stage `Nexus Push` à la place de `Docker Hub Push`/`Login`, et adapter `scripts/build-image.sh`, `scripts/trivy-image.sh`, `scripts/syft.sh` et `scripts/cosign.sh` (nom d'image, authentification) en conséquence.

---

### Phase 16 — VM2 : installation de K3s

```bash
sudo mkdir -p /etc/rancher/k3s
sudo nano /etc/rancher/k3s/config.yaml
```
```yaml
secrets-encryption: true
```

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.3+k3s1" sh -

sudo systemctl status k3s --no-pager
sudo k3s --version
sudo k3s kubectl get nodes    # doit afficher Ready / control-plane
```

Configuration de `kubectl` pour l'utilisateur courant :
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config

echo 'export KUBECONFIG="$HOME/.kube/config"' >> ~/.bashrc
source ~/.bashrc

kubectl config current-context
kubectl cluster-info
kubectl get nodes
kubectl get pods -A          # coredns, metrics-server, local-path-provisioner, traefik doivent être Running
kubectl get storageclass     # local-path doit être (default)
kubectl get ingressclass     # traefik doit être présent
kubectl get crd              # ingressroutes.traefik.io, middlewares.traefik.io, etc.
```

> **Remarque VPS** : `secrets-encryption: true` est particulièrement recommandé sur un VPS — sans cela, les Secrets Kubernetes ne sont protégés que par un encodage Base64, pas un chiffrement réel. Le port `6443` (API Kubernetes) ne doit être accessible que depuis le réseau privé/VPN de l'entreprise.

---

### Phase 17 — Installation de Helm (VM2)

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
helm list -A   # traefik et traefik-crd apparaissent, installés automatiquement par k3s
```

---

### Phase 18 — Connexion SSH Jenkins (VM1) → K3s (VM2)

```bash
# Sur VM1
ssh-keygen -t ed25519 -f ~/.ssh/jenkins_k3s -N ""
ssh-copy-id -i ~/.ssh/jenkins_k3s.pub <utilisateur>@<IP_VM2>

# Test
ssh -i ~/.ssh/jenkins_k3s <utilisateur>@<IP_VM2> "kubectl get nodes"
```

Dans Jenkins, créer le credential `k3s-ssh` (*SSH Username with private key*) avec cette clé privée.

---

### Phase 19 — Chart Helm de l'application et premier déploiement (VM2)

Structure du chart (déjà présente dans `kubernetes/charts/application/` du dépôt — voir [Structure du dépôt](#structure-du-dépôt) pour le détail des templates) :
```
application/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── nginx-configmap.yaml
    └── ingressroute.yaml
```

Créer le namespace applicatif et le Secret contenant les variables d'environnement Laravel (jamais écrites dans l'image ni les manifests) :
```bash
kubectl create namespace applications

kubectl create secret generic unicomnova-env \
  --namespace applications \
  --from-literal=APP_KEY="base64:$(openssl rand -base64 32)" \
  --from-literal=DB_CONNECTION=mysql \
  --from-literal=DB_HOST=<IP_BASE_DE_DONNEES> \
  --from-literal=DB_PORT=3306 \
  --from-literal=DB_DATABASE=<nom_base> \
  --from-literal=DB_USERNAME=<utilisateur> \
  --from-literal=DB_PASSWORD=<mot_de_passe>
```

> L'`APP_KEY` doit être générée une seule fois puis rester **stable** (ne pas la régénérer à chaque déploiement) — Laravel l'utilise pour le chiffrement, la changer casse le déchiffrement de données déjà chiffrées. En pratique, elle a été générée avec `php artisan key:generate --show` depuis l'application elle-même.

Premier déploiement (exécuté ensuite automatiquement par `scripts/deploy.sh` dans le pipeline — voir [Pipeline CI/CD](#pipeline-cicd)) :
```bash
helm upgrade --install application kubernetes/charts/application \
  --namespace applications \
  --set image.repository=<compte>/<application> \
  --set image.tag=<tag> \
  --set imagePullSecrets[0].name=dockerhub-registry \
  --set ingress.enabled=true \
  --set ingress.host=app.<IP_VM2>.nip.io \
  --set envFrom[0].secretRef.name=unicomnova-env

kubectl get pods -n applications
kubectl get deployment -n applications
## 23. Vérifier Readiness et Liveness

```bash
kubectl describe pod <POD> -n applications
```

Les probes utilisées dans la configuration stable :

```yaml
readinessProbe:
  httpGet:
    path: /
    port: http

livenessProbe:
  httpGet:
    path: /
    port: http
```

La Readiness contrôle l'admission du Pod dans le trafic. La Liveness permet à Kubernetes de redémarrer un conteneur qui ne fonctionne plus


> **Problème rencontré et corrigé durant le projet** : le premier déploiement a répondu en erreur HTTP 500, avec dans les logs `No application encryption key has been specified.` — le fichier `.env` n'existe volontairement pas dans le conteneur (Kubernetes injecte les variables via le Secret plutôt que de copier un `.env` dans l'image). La correction a consisté à bien injecter `APP_KEY` via `envFrom.secretRef` (déjà intégré dans le Secret ci-dessus).

> **Remarque sur la base de données** : voir [Base de données de l'application](#base-de-données-de-lapplication-laravellaragon) — en développement, la base tournait sur la machine hôte via Laragon (réseau `192.168.56.1`). **En production, remplacez `DB_HOST` par l'adresse d'une instance MySQL dédiée**, jamais un poste de développement.

---

### Phase 20 — Durcissement du déploiement Kubernetes (VM2)

Une fois le déploiement de base fonctionnel, le chart a été renforcé avec les Readiness/Liveness Probes, les limites CPU/mémoire et le SecurityContext (`runAsNonRoot`, `readOnlyRootFilesystem`, capacités Linux réduites) — voir le détail complet dans [Sécurité du déploiement Kubernetes](#sécurité-du-déploiement-kubernetes). Chaque modification a été validée avec :

```bash
helm lint kubernetes/charts/application
helm template kubernetes/charts/application
helm upgrade --install application kubernetes/charts/application -n applications -f <valeurs>
kubectl get pods -n applications
kubectl describe pod -n applications <nom-du-pod>
```

---

### Phase 21 — Kyverno et Monitoring (VM2)
## Installer Kyverno sur VM2

Ajouter le dépôt :

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
```

Installer dans son propre namespace :

```bash
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace
```

Vérifier :

```bash
kubectl get pods -n kyverno
kubectl get crd | grep kyverno
```

Kyverno fonctionne comme Admission Controller dans le cluster.
## Monitoring sur VM2

Avant installation :

```bash
kubectl get pods -A | grep -Ei 'prometheus|grafana|alertmanager|node-exporter|kube-state-metrics'
helm list -A
kubectl get svc -A | grep -Ei 'prometheus|grafana|alertmanager'
kubectl get storageclass
kubectl top nodes
free -h
```

Créer les fichiers de monitoring dans :

```text
kubernetes/monitoring/
```

## Installer Prometheus, Grafana, Alertmanager, Node Exporter et kube-state-metrics

Créer le fichier :

```bash
mkdir -p ~/devsecops-platform/kubernetes/monitoring
nano ~/devsecops-platform/kubernetes/monitoring/values-kube-prometheus-stack.yaml
```

Ajouter le dépôt Helm :

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Installer :

```bash
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f ~/devsecops-platform/kubernetes/monitoring/values-kube-prometheus-stack.yaml
```

Vérifier :

```bash
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
```

Le projet utilise des PVC pour conserver les données de monitoring après un redémarrage de Pod.

Dans l'environnement de développement validé :

```text
Prometheus    5Gi
Grafana       2Gi
Alertmanager  1Gi
Loki          5Gi
```

Adapter les tailles à la capacité de stockage du serveur de production.

## Gestion des problèmes de ressources du monitoring

Le déploiement initial a nécessité plusieurs ajustements.

Grafana a rencontré un `OOMKilled` pendant son démarrage. Sa mémoire a été augmentée progressivement et la liveness probe a été assouplie.

Prometheus Operator avait aussi rencontré un `CrashLoopBackOff` lié à l'absence de ressources garanties et à un démarrage plus lent que le délai de probe initial.

Pour une installation en production, vérifier systématiquement :

```bash
kubectl top nodes
kubectl top pods -n monitoring
kubectl describe node k3s-server
```

## Exposer Grafana avec Traefik

Créer :

```bash
nano ~/devsecops-platform/kubernetes/monitoring/grafana-ingressroute.yaml
```

Configuration :

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`grafana.<K3S_HOST>.nip.io`)
      kind: Rule
      services:
        - name: monitoring-grafana
          port: 80
```

Appliquer :

```bash
kubectl apply -f ~/devsecops-platform/kubernetes/monitoring/grafana-ingressroute.yaml
kubectl get ingressroute -n monitoring
```

## Installer Loki

Créer :

```bash
mkdir -p ~/devsecops-platform/kubernetes/monitoring/loki
nano ~/devsecops-platform/kubernetes/monitoring/loki/values-loki.yaml
```

Ajouter le dépôt :

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Installer :

```bash
helm install loki grafana/loki \
  --namespace monitoring \
  -f ~/devsecops-platform/kubernetes/monitoring/loki/values-loki.yaml
```

Le chart Loki utilisé exige une configuration explicite du `schemaConfig` et du stockage. Ces paramètres doivent être présents dans le fichier `values-loki.yaml`.

Vérifier :

```bash
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
```

## Collecte des logs avec Promtail

Dans la version utilisée dans le projet, Promtail est installé séparément du chart Loki.

Créer :

```bash
mkdir -p ~/devsecops-platform/kubernetes/monitoring/promtail
nano ~/devsecops-platform/kubernetes/monitoring/promtail/values-promtail.yaml
```

Installer :

```bash
helm install promtail grafana/promtail \
  --namespace monitoring \
  -f ~/devsecops-platform/kubernetes/monitoring/promtail/values-promtail.yaml
```

Promtail utilise la découverte Kubernetes des Pods pour collecter les logs et leur associer les labels :

```text
namespace
pod
app
container
```

Vérifier :

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=50
```

Ajouter Loki dans Grafana :

```text
Connections
→ Data sources
→ Add data source
→ Loki
```

URL :

```text
http://loki:3100
```

Tester la connexion.

## Dashboards Grafana

Importer les dashboards adaptés depuis la bibliothèque Grafana.

Pour les dashboards Kubernetes, utiliser une source Prometheus.

Pour les logs, utiliser la source Loki.

Toujours vérifier que les dashboards correspondent aux métriques effectivement collectées par la version installée de kube-prometheus-stack.

## Vérification finale du monitoring

```bash
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
kubectl get svc -n monitoring
kubectl get servicemonitor -n monitoring
kubectl get prometheus -n monitoring
kubectl get alertmanager -n monitoring
```

Vérifier les ressources :

```bash
kubectl top nodes
kubectl top pods -n monitoring
```

Vérifier Prometheus :


Vérifier Grafana via Traefik :


```
http://grafana.<K3S_HOST>
```

Vérifier Loki :

```bash
kubectl run loki-test -n monitoring --rm -it \
  --image=curlimages/curl:8.10.1 \
  --restart=Never -- \
  curl -m 5 http://loki:3100/ready
```

Une réponse :

```text
ready
```

confirme que Loki est accessible depuis le réseau Kubernetes.


Voir les sections dédiées : [Kyverno — Policy Engine](#kyverno--policy-engine) et [Monitoring et observabilité](#monitoring-et-observabilité) pour l'installation détaillée (charts `kyverno`, `kube-prometheus-stack`, `loki`, `promtail`), déjà versionnés dans `kubernetes/kyverno/` et `kubernetes/monitoring/` du dépôt.




---

### Phase 22 — Déclenchement automatique du pipeline (VM1)

Voir [Déclenchement automatique du pipeline](#déclenchement-automatique-du-pipeline-webhook--smee) pour la configuration complète du Generic Webhook Trigger et du webhook GitHub.

> **Remarque VPS — recommandation forte** : le relais **Smee** (utilisé en développement car Jenkins n'est pas exposé publiquement) **ne doit pas être conservé en production**. Sur un serveur d'entreprise avec Jenkins accessible via un nom de domaine et un reverse proxy HTTPS, configurez directement la **Payload URL** du webhook GitHub vers `https://<votre-domaine>/generic-webhook-trigger/invoke?token=xxxxxx`, sans passer par `smee.io`.

---

### Résumé — ordre d'installation pour un déploiement VPS

```
VM1 (DevSecOps)                          VM2 (Kubernetes)
──────────────────────                   ──────────────────────
1.  Système + Docker                     1.  Système
2.  Arborescence + réseau Docker         2.  K3s
3.  Jenkins (image + compose + plugins)  3.  kubectl (config utilisateur)
4.  SonarQube + PostgreSQL               4.  Helm (Traefik inclus)
5.  Intégration Jenkins ↔ SonarQube      5.  Namespace + Secret applicatif
6.  Vault (mode file, jamais -dev)       6.  Chart Helm + 1er déploiement
7.  Secrets Vault + clés Cosign          7.  Durcissement sécurité (probes,
8.  Dépôt Git + PAT GitHub                   ressources, SecurityContext)
9.  Job Pipeline Jenkins                 8.  Kyverno (policy Audit)
10. Paramétrage générique                9.  Monitoring (Prometheus/Grafana/
    (APP_REPOSITORY/APP_BRANCH)              Loki/Promtail)
11. detect-project.sh
12. Retrieve Secrets (Vault → Jenkins)   ──────────────────────
13. Build, SonarQube, Dependency-Check,           ▲
    Gitleaks, Checkov                              │
14. Docker Hub (ou Nexus)                 Connexion SSH (étape 18, VM1→VM2)
15. Clé SSH → VM2
16. Webhook GitHub + reverse proxy
    (pas de Smee en production)
```

## Mise en production — ce qui reste à durcir

L'environnement actuel est un environnement de **développement/démonstration** sur deux VM locales. Avant tout déploiement en production (VPS privé, cible finale prévue par le cahier des charges), les points suivants doivent impérativement être traités :

### Chiffrement et certificats SSL/TLS

| Composant | État actuel | À faire en production |
|---|---|---|
| Vault | `tls_disable = 1`, écoute en HTTP simple | Activer un `listener "tcp"` avec certificat TLS (`tls_cert_file`, `tls_key_file`), passer en `https://` |
| Traefik | `entryPoints: web` (port 80, HTTP uniquement) | Ajouter un `entryPoint websecure` (port 443) avec un `certResolver` Let's Encrypt (ACME), rediriger `web → websecure` |
| Grafana / application | Exposées en HTTP via `*.nip.io` | Passer par un vrai nom de domaine + certificat TLS (Let's Encrypt via Traefik, ou certificat interne) |
| Jenkins | Exposé en HTTP sur le port 8080 | Placer Jenkins derrière un reverse proxy (Traefik/Nginx) avec TLS, ne plus exposer le port 8080 directement |
| Webhook GitHub | Relayé via Smee.io (service tiers public) | Exposer Jenkins directement via une URL HTTPS publique (reverse proxy + certificat), configurer le webhook GitHub avec cette URL directement — supprimer la dépendance à Smee |

### Ports et exposition réseau

| Port | Service | Recommandation en production |
|---|---|---|
| 8080 | Jenkins (HTTP) | Ne pas exposer publiquement ; accès via reverse proxy HTTPS uniquement |
| 8200 | Vault (HTTP) | Idem : accès interne uniquement, ou HTTPS avec authentification renforcée |
| 9000 | SonarQube | Accès restreint au réseau interne |
| 5432 | PostgreSQL (SonarQube) | Ne jamais exposer publiquement ; garder en interne au réseau Docker |
| 80 (web) | Traefik (HTTP) | Conserver uniquement pour la redirection vers 443 |
| 443 (websecure) | Traefik (HTTPS) | Port public à ouvrir pour l'accès à l'application et à Grafana |
| 3306 | MySQL (Laragon) | Restreindre l'accès au seul réseau privé VM ↔ hôte, jamais exposé sur Internet |

### Autres points de durcissement

- **Vault** : passer d'un `root token` unique à une politique d'accès granulaire (policies Vault par service), et envisager l'auto-unseal (KMS cloud) plutôt qu'un unseal manuel après chaque redémarrage.
- **Kyverno** : basculer la policy `security-baseline` du mode `Audit` au mode `Enforce` (voir [Évolutions prévues](#évolutions-prévues)).
- **Secrets Kubernetes** : envisager un chiffrement des Secrets at-rest plus robuste que l'encodage Base64 natif (déjà activé côté K3s via `secrets-encryption: true`, à vérifier/étendre en production).
- **Mot de passe Grafana** : remplacer `adminPassword` en clair dans `values-kube-prometheus-stack.yaml` par un Secret Kubernetes dédié, non versionné.
- **Base de données applicative** : en production, ne pas dépendre d'une instance MySQL sur poste de développement (Laragon) — migrer vers une instance MySQL dédiée, sauvegardée et supervisée.
- **Webhook GitHub** : une fois Jenkins exposé en HTTPS, remplacer le relais Smee par une Payload URL directe vers Jenkins.

## État d'avancement

| Fonctionnalité | Statut |
|---|---|
| Pipeline CI/CD complet (Jenkins) | ✅ Fonctionnel |
| SonarQube, Gitleaks, OWASP Dependency-Check | ✅ Fonctionnel |
| Checkov (analyse IaC, non bloquant) | ✅ Fonctionnel |
| Build, scan et signature des images (Trivy, Syft, Cosign) | ✅ Fonctionnel |
| Publication Docker Hub | ✅ Fonctionnel |
| Gestion des secrets via Vault | ✅ Fonctionnel |
| Déploiement Kubernetes via Helm | ✅ Fonctionnel |
| Sécurisation du déploiement (SecurityContext, probes, ressources) | ✅ Fonctionnel |
| Kyverno (mode Audit) | ✅ Fonctionnel |
| Monitoring (Prometheus, Grafana, Alertmanager) | ✅ Fonctionnel |
| Centralisation des journaux (Loki, Promtail) | ✅ Fonctionnel |
| Notifications SMTP / Microsoft Teams | 🚧 Non implémenté |


## Évolutions prévues

- **Kyverno** : passage du mode `Audit` au mode `Enforce`, après validation de tests de rejet volontaire.
- **Notifications** : intégration SMTP / Microsoft Teams pour les alertes de pipeline et de sécurité.
- **Migration** : déploiement de la plateforme sur un VPS privé, conformément à l'architecture prévue.

---

*Projet réalisé dans le cadre d'un Projet de Fin d'Année (PFA).*
