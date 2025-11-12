#!/bin/bash
APP_DIR="/var/www/simple-node-app/app"
LOG_FILE="/var/www/simple-node-app/app.log"

echo "Starting Node.js app..." | tee -a "$LOG_FILE"

# Install Node.js 18 if not already installed
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
  yum install -y nodejs
fi

# cd "$APP_DIR" || exit 1
cd "$APP_DIR" || { echo "Failed to access $APP_DIR"; exit 1; }

# Install dependencies
npm install >> "$LOG_FILE" 2>&1

# Stop any running Node process
pkill -f "node app.js" || true

# Start the app in background
nohup node app.js >> "$LOG_FILE" 2>&1 &

echo "Node.js app started on port 8080" | tee -a "$LOG_FILE"

################################
# #!/bin/bash
# APP_DIR="/var/www/simple-node-app"
# LOG_FILE="$APP_DIR/app.log"

# echo "Starting Node.js app..." | tee -a "$LOG_FILE"

# # Node.js 18 is available via dnf in Amazon Linux 2023
# dnf install -y nodejs

# cd "$APP_DIR" || exit 1
# npm install >> "$LOG_FILE" 2>&1
# pkill -f "node" || true
# nohup npm start >> "$LOG_FILE" 2>&1 &
# echo "Node.js app started." | tee -a "$LOG_FILE"

#############################
# #!/bin/bash
# APP_DIR=/var/www/simple-node-app
# cd $APP_DIR || exit 1
# if ! command -v node >/dev/null; then
#   curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
#   yum install -y nodejs
# fi
# npm install
# nohup npm start > app.log 2>&1 &

