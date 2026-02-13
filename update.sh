#!/bin/bash
set -e

OPENCLAW_SRC="${OPENCLAW_SRC:-/root/openclaw}"

echo "Pulling latest source..."
git -C "$OPENCLAW_SRC" pull

echo "Rebuilding base image..."
docker build -t openclaw:base "$OPENCLAW_SRC"

echo "Rebuilding skills layer..."
docker compose build --no-cache

echo "Restarting containers..."
docker compose up -d

echo "Done! Run 'openclaw doctor' inside the container to verify."
