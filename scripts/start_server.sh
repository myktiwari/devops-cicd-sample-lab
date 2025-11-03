#!/bin/bash
APP_DIR=/var/www/simple-node-app
cd $APP_DIR || exit 1
if ! command -v node >/dev/null; then
  curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
  yum install -y nodejs
fi
npm install
nohup npm start > app.log 2>&1 &
