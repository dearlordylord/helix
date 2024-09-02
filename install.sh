#!/bin/bash

# Install:
# curl -LO https://get.helix.ml/install-helix.sh && chmod +x install-helix.sh

set -euo pipefail

echo -e "\033[1;91m"
echo -ne " ░█░█░█▀▀░█░░░▀█▀░█░█░░░░█▄█░█░░"
echo -ne "\033[0m"
echo -e "\033[1;93m"
echo -ne " ░█▀█░█▀▀░█░░░░█░░▄▀▄░░░░█░█░█░░"
echo -ne "\033[0m"
echo -e "\033[1;92m"
echo -ne " ░▀░▀░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░░▀░▀░▀▀▀"
echo -e "\033[0m"
echo -e "\033[1;96m              Private GenAI Stack\033[0m"
echo

set -euo pipefail

# Default values
AUTO=true
CLI=false
CONTROLPLANE=false
RUNNER=false
LARGE=false
API_HOST=""
RUNNER_TOKEN=""
TOGETHERAI_TOKEN=""
AUTO_APPROVE=false

# Determine OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Determine latest release
LATEST_RELEASE=$(curl -s https://api.github.com/repos/helixml/helix/releases/latest | sed -n 's/.*"tag_name": "\(.*\)".*/\1/p')

# Set binary name
BINARY_NAME="helix-${OS}-${ARCH}"

# Set installation directory
if [ "$OS" = "linux" ]; then
    INSTALL_DIR="/opt/HelixML"
elif [ "$OS" = "darwin" ]; then
    INSTALL_DIR="$HOME/HelixML"
fi


# Function to display help message
display_help() {
    cat << EOF
Usage: ./install.sh [OPTIONS]

Options:
  --cli                    Install the CLI (binary in /usr/local/bin)
  --controlplane           Install the controlplane (API, Postgres etc in Docker Compose in $INSTALL_DIR)
  --runner                 Install the runner (single container with runner.sh script to start it in $INSTALL_DIR)
  --large                  Install the large version of the runner (includes all models, 100GB+ download, otherwise uses small one)
  --api-host <host>        Specify the API host for the API to serve on and/or the runner to connect to, e.g. http://localhost:8080 or https://my-controlplane.com. Will install and configure Caddy if HTTPS and running on Ubuntu.
  --runner-token <token>   Specify the runner token when connecting a runner to an existing controlplane
  --togetherai-token <token> Specify the together.ai token for inference, rag and apps without a GPU
  -y                       Auto approve the installation

Examples:

1. Install the CLI, the controlplane and a runner if a GPU is available (auto mode):
   ./install-helix.sh

2. Install just the CLI:
   ./install-helix.sh --cli

3. Install CLI and controlplane with external TogetherAI token:
   ./install-helix.sh --cli --controlplane --togetherai-token YOUR_TOGETHERAI_TOKEN

4. Install CLI and controlplane (to install runner separately):
   ./install-helix.sh --cli --controlplane

5. Install CLI, controlplane, and runner on a node with a GPU:
   ./install-helix.sh --cli --controlplane --runner

6. Install just the runner, pointing to a controlplane with a DNS name (find runner token in /opt/HelixML/.env):
   ./install-helix.sh --runner --api-host your-controlplane-domain.com --runner-token YOUR_RUNNER_TOKEN

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            display_help
            exit 0
            ;;
        --cli)
            CLI=true
            AUTO=false
            shift
            ;;
        --controlplane)
            CONTROLPLANE=true
            AUTO=false
            shift
            ;;
        --runner)
            RUNNER=true
            AUTO=false
            shift
            ;;
        --large)
            LARGE=true
            shift
            ;;
        --api-host)
            API_HOST=$2
            shift 2
            ;;
        --runner-token)
            RUNNER_TOKEN="$2"
            shift 2
            ;;
        --togetherai-token)
            TOGETHERAI_TOKEN="$2"
            shift 2
            ;;
        -y)
            AUTO_APPROVE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            display_help
            exit 1
            ;;
    esac
done

# Adjust default values based on provided arguments and AUTO mode
if [ "$AUTO" = true ]; then
    CLI=true
    CONTROLPLANE=true
    if command -v nvidia-smi &> /dev/null; then
        RUNNER=true
    fi
    echo -e "Auto-install mode detected. Installing CLI and Control Plane.\n"
    if command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA GPU detected. Runner will be installed locally."
    else
        echo "No NVIDIA GPU detected. Runner will not be installed. If you want to connect "
        echo "an external GPU node to this controlplane, you need to point a DNS name at "
        echo "the IP address of this server and set --api-host, for example "
        echo "https://my-controlplane.com"
        echo
        echo "See command at the end to install runner separately on a GPU node, or pass "
        echo "--togetherai-token to connect to together.ai for LLM inference."
        echo
    fi
fi

if [ "$RUNNER" = true ] && [ "$CONTROLPLANE" = false ] && [ -z "$API_HOST" ]; then
    echo "Error: When installing only the runner, you must specify --api-host and --runner-token"
    echo "to connect to an external controlplane, for example:"
    echo "./install.sh --runner --api-host your-controlplane-domain.com --runner-token YOUR_RUNNER_TOKEN"
    exit 1
fi

# Function to gather planned modifications
gather_modifications() {
    local modifications=""
    
    if [ "$CLI" = true ]; then
        modifications+="  - Install Helix CLI\n"
    fi
    
    if [ "$CONTROLPLANE" = true ]; then
        modifications+="  - Ensure Docker and Docker Compose plugin are installed\n"
        modifications+="  - Install Helix Control Plane\n"
    fi

    if [ "$RUNNER" = true ]; then
        modifications+="  - Ensure Docker and Docker Compose plugin are installed\n"
        modifications+="  - Ensure NVIDIA Docker runtime is installed (if GPU is available)\n"
        modifications+="  - Install Helix Runner\n"
    fi
    
    echo -e "$modifications"
}

# Function to ask for user approval
ask_for_approval() {
    if [ "$AUTO_APPROVE" = true ]; then
        return 0
    fi
    
    echo "┌───────────────────────────────────────────────────────────────────────────┐"
    echo "│ The following modifications will be made to your system:                  │"
    echo "└───────────────────────────────────────────────────────────────────────────┘"
    echo
    gather_modifications
    echo "┌───────────────────────────────────────────────────────────────────────────┐"
    echo "│ If this is not what you want, re-run the script with --help at the end to │"
    echo "│ see other options.                                                        │"
    echo "└───────────────────────────────────────────────────────────────────────────┘"
    echo
    read -p "Do you want to proceed? (y/N) " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            echo "Installation aborted."
            exit 1
            ;;
    esac
}

# Ask for user approval before proceeding
ask_for_approval

sudo mkdir -p $INSTALL_DIR
# Change the owner of the installation directory to the current user
sudo chown -R $(id -un):$(id -gn) $INSTALL_DIR
mkdir -p $INSTALL_DIR/data/helix-{postgres,filestore,pgvector}
mkdir -p $INSTALL_DIR/scripts/postgres/

# Install CLI if requested or in AUTO mode
if [ "$CLI" = true ]; then
    echo -e "\nDownloading Helix CLI..."
    sudo curl -L "https://github.com/helixml/helix/releases/download/${LATEST_RELEASE}/${BINARY_NAME}" -o /usr/local/bin/helix
    sudo chmod +x /usr/local/bin/helix
    echo "Helix CLI has been installed to /usr/local/bin/helix"
fi

# Function to generate random alphanumeric password
generate_password() {
    openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16
}

# Function to install Docker and Docker Compose plugin
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Installing Docker..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                ubuntu|debian)
                    sudo apt-get update
                    sudo apt-get install -y ca-certificates curl gnupg
                    sudo install -m 0755 -d /etc/apt/keyrings
                    curl -fsSL https://download.docker.com/linux/$ID/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                    sudo chmod a+r /etc/apt/keyrings/docker.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                    sudo apt-get update
                    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                    ;;
                fedora)
                    sudo dnf -y install dnf-plugins-core
                    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                    sudo systemctl start docker
                    sudo systemctl enable docker
                    ;;
                *)
                    echo "Unsupported distribution for automatic Docker installation. Please install Docker manually."
                    exit 1
                    ;;
            esac
        else
            echo "Unable to determine OS distribution. Please install Docker manually."
            exit 1
        fi
    fi

    if ! docker compose version &> /dev/null; then
        echo "Docker Compose plugin not found. Installing Docker Compose plugin..."
        sudo apt-get update
        sudo apt-get install -y docker-compose-plugin
    fi
}

# Function to install NVIDIA Docker runtime
install_nvidia_docker() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA GPU not detected. Skipping NVIDIA Docker runtime installation."
        return
    fi

    if ! docker info | grep -i nvidia &> /dev/null; then
        echo "NVIDIA Docker runtime not found. Installing NVIDIA Docker runtime..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                ubuntu|debian)
                    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
                    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
                    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
                    sudo apt-get update
                    sudo apt-get install -y nvidia-docker2
                    sudo systemctl restart docker
                    ;;
                fedora)
                    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
                    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | sudo tee /etc/yum.repos.d/nvidia-docker.repo
                    sudo dnf install -y nvidia-docker2
                    sudo systemctl restart docker
                    ;;
                *)
                    echo "Unsupported distribution for automatic NVIDIA Docker runtime installation. Please install NVIDIA Docker runtime manually."
                    exit 1
                    ;;
            esac
        else
            echo "Unable to determine OS distribution. Please install NVIDIA Docker runtime manually."
            exit 1
        fi
    fi
}

# Install controlplane if requested or in AUTO mode
if [ "$CONTROLPLANE" = true ]; then
    install_docker
    echo -e "\nDownloading docker-compose.yaml..."
    sudo curl -L "https://github.com/helixml/helix/releases/download/${LATEST_RELEASE}/docker-compose.yaml" -o $INSTALL_DIR/docker-compose.yaml
    echo "docker-compose.yaml has been downloaded to $INSTALL_DIR/docker-compose.yaml"

    # Create database creation script
    cat << EOF > "$INSTALL_DIR/scripts/postgres/postgres-db.sh"
#!/bin/bash

set -e
set -u

function create_user_and_database() {
	local database=\$1
	echo "  Creating database '\$database'"
	psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" <<-EOSQL
	    CREATE DATABASE \$database;
EOSQL
}

if [ -n "\$POSTGRES_DATABASES" ]; then
	echo "Database creation requested: \$POSTGRES_DATABASES"
	for db in $(echo \$POSTGRES_DATABASES | tr ',' ' '); do
		create_user_and_database \$db
	done
	echo "databases created"
fi
EOF
    chmod +x $INSTALL_DIR/scripts/postgres/postgres-db.sh

    # Create .env file
    ENV_FILE="$INSTALL_DIR/.env"
    echo -e "\nCreating .env file..."
    
    # Set domain
    if [ -z "$API_HOST" ]; then
        DOMAIN="http://localhost:8080"
    else
        DOMAIN="https://${API_HOST}"
    fi

    # Generate .env content
    cat << EOF > "$ENV_FILE"
# Set passwords
KEYCLOAK_ADMIN_PASSWORD=$(generate_password)
POSTGRES_ADMIN_PASSWORD=$(generate_password)
RUNNER_TOKEN=${RUNNER_TOKEN:-$(generate_password)}

# URLs
KEYCLOAK_FRONTEND_URL=${DOMAIN}/auth/
SERVER_URL=${DOMAIN}

# Storage
# Uncomment the lines below if you want to persist direct to disk. You may need to set up the
# directory user and group on the filesystem and in the docker-compose.yaml file.
#POSTGRES_DATA=$INSTALL_DIR/data/helix-postgres
#FILESTORE_DATA=$INSTALL_DIR/data/helix-filestore
#PGVECTOR_DATA=$INSTALL_DIR/data/helix-pgvector

# Optional integrations:

## External LLM provider
EOF

    # Add TogetherAI configuration if token is provided
    if [ -n "$TOGETHERAI_TOKEN" ]; then
        cat << EOF >> "$ENV_FILE"
INFERENCE_PROVIDER=togetherai
TOGETHER_API_KEY=$TOGETHERAI_TOKEN
EOF
    fi

    # Continue with the rest of the .env file
    cat << EOF >> "$ENV_FILE"

## Analytics
# GOOGLE_ANALYTICS_FRONTEND=
# SENTRY_DSN_FRONTEND=
# SENTRY_DSN_API=

## Notifications
# EMAIL_SMTP_HOST=smtp.example.com
# EMAIL_SMTP_PORT=25
# EMAIL_SMTP_USERNAME=REPLACE_ME
# EMAIL_SMTP_PASSWORD=REPLACE_ME

# EMAIL_MAILGUN_DOMAIN=REPLACE_ME
# EMAIL_MAILGUN_API_KEY=REPLACE_ME
EOF

    echo ".env file has been created at $ENV_FILE"
    echo -e "\nYou can now 'cd $INSTALL_DIR' and run 'docker compose up -d' to start Helix"
    echo "Helix will be available at $DOMAIN"

    # Install Caddy if API_HOST is an HTTPS URL and system is Ubuntu
    if [[ "$API_HOST" == https* ]]; then
        if [[ "$ID" != "ubuntu" ]]; then
            echo "Caddy installation is only supported on Ubuntu. Please install and configure Caddy manually (check the install.sh script for details)."
        else
            echo "Installing Caddy..."
            sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo apt-key add -
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
            sudo apt-get update
            sudo apt-get install caddy

            # Create Caddyfile
            CADDYFILE="/etc/caddy/Caddyfile"
            echo "Creating Caddyfile..."
            # Strip https:// and port from API_HOST
            CADDY_HOST=$(echo "$API_HOST" | sed -e 's/^https:\/\///' -e 's/:.*//')
            cat << EOF > "$CADDYFILE"
$CADDY_HOST {
    reverse_proxy localhost:8080
}
EOF
            echo "Caddyfile has been created at $CADDYFILE"
            echo "Please start Caddy manually after starting the Docker Compose stack:"
            echo "sudo systemctl restart caddy"
        fi
    fi
fi

# Install runner if requested or in AUTO mode with GPU
if [ "$RUNNER" = true ]; then
    install_docker
    install_nvidia_docker
    # Check for NVIDIA GPU
    if ! command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA GPU not detected. Skipping runner installation."
        echo "Set up a runner separately, per https://docs.helix.ml/helix/private-deployment/controlplane/#attaching-a-runner"
        exit 1
    fi

    # Determine GPU memory
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | awk '{print int($1/1024)}')

    # Determine runner tag and warmup models
    if [ "$LARGE" = true ]; then
        RUNNER_TAG="${LATEST_RELEASE}-large"
        WARMUP_MODELS=""
    else
        RUNNER_TAG="${LATEST_RELEASE}-small"
        WARMUP_MODELS="llama3:instruct,phi3:instruct"
    fi

    # Determine runner token
    if [ -z "$RUNNER_TOKEN" ]; then
        if [ -f "$INSTALL_DIR/.env" ]; then
            RUNNER_TOKEN=$(grep RUNNER_TOKEN $INSTALL_DIR/.env | cut -d '=' -f2)
        else
            echo "Error: RUNNER_TOKEN not found in .env file and --runner-token not provided."
            echo "Please provide the runner token using the --runner-token argument."
            exit 1
        fi
    fi

    # Create runner.sh
    cat << EOF > $INSTALL_DIR/runner.sh
#!/bin/bash

# Configuration variables
RUNNER_TAG="${RUNNER_TAG}"
api_host="${API_HOST}"
GPU_MEMORY="${GPU_MEMORY}"
WARMUP_MODELS="${WARMUP_MODELS}"
RUNNER_TOKEN="${RUNNER_TOKEN}"

# Set warmup models parameter
if [ -n "\$WARMUP_MODELS" ]; then
    WARMUP_MODELS_PARAM="-e RUNTIME_OLLAMA_WARMUP_MODELS=\$WARMUP_MODELS"
else
    WARMUP_MODELS_PARAM=""
fi

# Check if api-1 container is running
if sudo docker ps --format '{{.Image}}' | grep 'registry.helix.ml/helix/controlplane'; then
    api_host="http://api:80"
    echo "Detected controlplane container running. Setting API_HOST to \${api_host}"
fi

# Run the docker container
sudo docker run --privileged --gpus all --shm-size=10g \\
    --restart=always -d \\
    --name helix-runner --ipc=host --ulimit memlock=-1 \\
    --ulimit stack=67108864 \\
    --network="helix_default" \\
    -v \${HOME}/.cache/huggingface:/root/.cache/huggingface \\
    \${WARMUP_MODELS_PARAM} \\
    registry.helix.ml/helix/runner:\${RUNNER_TAG} \\
    --api-host \${api_host} --api-token \${RUNNER_TOKEN} \\
    --runner-id \$(hostname) \\
    --memory \${GPU_MEMORY}GB \\
    --allow-multiple-copies
EOF

    sudo chmod +x $INSTALL_DIR/runner.sh
    echo "Runner script has been created at $INSTALL_DIR/runner.sh"
    echo "To start the runner, run: sudo $INSTALL_DIR/runner.sh"
    if [ -z "$API_HOST" ]; then
        echo
        echo "To connect an external runner to this controlplane, run on a node with a GPU:"
        echo "bash <(curl -Ls https://get.helix.ml/) --runner --api-host https://your-controlplane-domain.com --runner-token YOUR_RUNNER_TOKEN"
        echo "You can find the runner token in $INSTALL_DIR/.env"
    fi
fi

echo -e "\nInstallation complete."