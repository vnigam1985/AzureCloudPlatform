#!/bin/bash

# === CONFIGURATION ===
PROXY_ADDRESS="http://your.proxy.ip:port"
TARGET_URL="https://www.google.com"
LOG_FILE_JSON="/var/log/proxy_health.log"
LOG_FILE_CSV="/var/log/proxy_health.csv"
DURATION_SECONDS=600
SLEEP_INTERVAL=1

# === Timer Setup ===
START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION_SECONDS))

# === OPTIONAL: CSV Header (Uncomment to use CSV) ===
# if [ ! -f "$LOG_FILE_CSV" ]; then
#     echo "TimeGenerated,ProxyStatus,HttpStatus,ResponseTime_ms" > "$LOG_FILE_CSV"
# fi

while [ $(date +%s) -lt $END_TIME ]; do
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    CURL_OUTPUT=$(curl -x $PROXY_ADDRESS -o /dev/null -s -w "%{http_code} %{time_total}" --max-time 10 $TARGET_URL)
    CURL_EXIT=$?

    HTTP_STATUS=$(echo $CURL_OUTPUT | awk '{print $1}')
    RESPONSE_TIME=$(echo $CURL_OUTPUT | awk '{print $2}')
    RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc)
    STATUS="DOWN"

    if [[ $CURL_EXIT -eq 0 && $HTTP_STATUS -eq 200 ]]; then
        STATUS="UP"
    fi

    # === NDJSON Log Line ===
    echo "{\"TimeGenerated\":\"$TIMESTAMP\",\"ProxyStatus\":\"$STATUS\",\"HttpStatus\":$HTTP_STATUS,\"ResponseTime_ms\":$RESPONSE_TIME_MS}" >> "$LOG_FILE_JSON"

    # === CSV Log Line (Uncomment to use CSV) ===
    # echo "$TIMESTAMP,$STATUS,$HTTP_STATUS,$RESPONSE_TIME_MS" >> "$LOG_FILE_CSV"

    sleep $SLEEP_INTERVAL
done
