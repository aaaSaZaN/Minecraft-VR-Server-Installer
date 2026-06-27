#!/bin/bash
while true; do
  echo "Starting bot..."
  node index.js
  echo "Bot crashed or ended, restarting in 5 seconds..."
  sleep 5
done
