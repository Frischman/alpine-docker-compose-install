#!/bin/sh

set -eu # 任何命令失败都立即退出，并禁止使用未声明的变量

log_error() {
  echo "Error: $*" >&2 # 将错误信息输出到 stderr
}

cleanup() {
  echo "Cleaning up temporary files..."
  rm -rf "$TEMP_DIR"
  if [ -f /etc/apk/repositories.bak ]; then
    mv /etc/apk/repositories.bak /etc/apk/repositories
  fi
}

trap cleanup EXIT

echo "Creating temporary directory..."
TEMP_DIR=$(mktemp -d) || { log_error "Failed to create temporary directory."; exit 1; }

echo "Updating apk repositories..."
apk update || { log_error "Failed to update apk repositories."; exit 1; }

# 自动检测 Alpine 版本，处理 edge 和其他特殊情况
if grep -q "edge" /etc/alpine-release; then
  ALPINE_VERSION="edge"
elif grep -q "v" /etc/alpine-release; then
  ALPINE_VERSION=$(cat /etc/alpine-release | cut -d'.' -f1,2)
elif grep -q "[0-9]" /etc/alpine-release; then # 兼容没有 "v" 的数字版本号
  ALPINE_VERSION="v$(cat /etc/alpine-release | cut -d'.' -f1,2)"
else
  log_error "Could not determine Alpine version. /etc/alpine-release format is unexpected."
  exit 1
fi

echo "Detected Alpine version: ${ALPINE_VERSION}"

# 备份 /etc/apk/repositories 文件
if [ -f /etc/apk/repositories ]; then
  echo "Backing up existing /etc/apk/repositories file..."
  cp /etc/apk/repositories /etc/apk/repositories.bak || { log_error "Failed to backup /etc/apk/repositories"; exit 1; }
fi

# 创建 /etc/apk/repositories 文件并添加 main 和 community 仓库
echo "Creating /etc/apk/repositories file..."
echo "http://dl-cdn.alpinelinux.org/alpine/${ALPINE_VERSION}/main" > /etc/apk/repositories || { log_error "Failed to add main repository"; exit 1; }
echo "http://dl-cdn.alpinelinux.org/alpine/${ALPINE_VERSION}/community" >> /etc/apk/repositories || { log_error "Failed to add community repository"; exit 1; }

apk update || { log_error "Failed to update apk after adding repositories"; exit 1; }

echo "Installing dependencies..."
apk add --no-cache \
    ca-certificates \
    curl \
    iptables \
    iproute2 \
    e2fsprogs-libs \
    libseccomp || { log_error "Failed to install dependencies."; exit 1; }

echo "Installing Docker..."
apk add --no-cache docker || { log_error "Failed to install Docker."; exit 1; }

echo "Starting Docker service..."
rc-update add docker boot || { log_error "Failed to add Docker to boot."; exit 1; }
rc-service docker start || { log_error "Failed to start Docker service."; exit 1; }

# 检查 docker 是否启动成功，增加等待时间并在失败时重试
RETRY_COUNT=5
RETRY_DELAY=5

for i in $(seq 1 $RETRY_COUNT); do
  if docker info > /dev/null 2>&1; then
    echo "Docker service started successfully."
    break
  else
    echo "Waiting for Docker service to start... ($i/$RETRY_COUNT)"
    sleep $RETRY_DELAY
  fi

  if [ $i -eq $RETRY_COUNT ]; then
    log_error "Docker service failed to start after $((RETRY_COUNT * RETRY_DELAY)) seconds. Check logs with 'rc-status -a docker' or 'logread'."
    exit 1
  fi
done

echo "Downloading Docker Compose..."
# 获取最新的 docker-compose 版本，并处理网络问题
COMPOSE_URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep browser_download_url | grep "docker-compose-$(uname -s)-$(uname -m)" | cut -d '"' -f4)
if [ -z "$COMPOSE_URL" ]; then
  log_error "Could not determine latest Docker Compose URL for this architecture. Check your internet connection or GitHub API availability."
  exit 1
fi

curl -L "$COMPOSE_URL" -o "$TEMP_DIR/docker-compose" || { log_error "Error downloading Docker Compose. Check your internet connection."; exit 1; }

echo "Setting execute permissions for Docker Compose..."
chmod +x "$TEMP_DIR/docker-compose" || { log_error "Failed to set execute permissions for Docker Compose."; exit 1; }

echo "Moving Docker Compose to final destination..."
mv "$TEMP_DIR/docker-compose" /usr/local/bin/docker-compose || { log_error "Failed to move Docker Compose to final destination."; exit 1; }

echo "Creating symbolic link for Docker Compose..."
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || { log_error "Failed to create symbolic link for Docker Compose."; exit 1; }

echo "Verifying installation..."
docker version || log_error "Failed to verify Docker installation."
docker-compose version || log_error "Failed to verify Docker Compose installation."

# 清理备份文件
if [ -f /etc/apk/repositories.bak ]; then
  rm /etc/apk/repositories.bak
fi

echo "Docker and Docker Compose installed successfully on Alpine ${ALPINE_VERSION}!"
