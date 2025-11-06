#!/bin/bash
echo "Stopping Node.js app if running..."
pkill -f "node" || true
