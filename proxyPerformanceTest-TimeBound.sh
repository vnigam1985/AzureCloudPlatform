#!/bin/bash

# === CONFIGURATION ===
PROXY_ADDRESS="http://your.proxy.ip:port"
TARGET_URL="https://www.google.com"
LOG_FILE_JSON="/var/log/proxy_health.log"
LOG_FILE_CSV="/var/log/proxy_health.csv"
DURATION_SECONDS=60
SLEEP_INTERVAL=1

# === METRICS INITIALIZATION ===
TOTAL_RUNS=0
UP_COUNT=0
DOWN_COUNT=0
TOTAL_RESPONSE_TIME=0
MIN_RESPONSE_TIME=999999
MAX_RESPONSE_TIME=0
TOTAL_BYTES_DOWNLOADED=0
TOTAL_SPEED_MBPS=0

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION_SECONDS))

# === OPTIONAL: CSV HEADER ===
# if [ ! -f "$LOG_FILE_CSV" ]; then
#     echo "TimeGenerated,ProxyStatus,HttpStatus,ResponseTime_ms,SizeDownloaded_MB,DownloadSpeed_mbps" > "$LOG_FILE_CSV"
# fi

while [ $(date +%s) -lt $END_TIME ]; do
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    CURL_OUTPUT=$(curl -x "$PROXY_ADDRESS" -o /dev/null -s -w "%{http_code} %{time_total} %{size_download} %{speed_download}" --max-time 10 "$TARGET_URL")
    CURL_EXIT=$?

    HTTP_STATUS=$(echo "$CURL_OUTPUT" | awk '{print $1}')
    RESPONSE_TIME=$(echo "$CURL_OUTPUT" | awk '{print $2}')
    SIZE_DOWNLOADED=$(echo "$CURL_OUTPUT" | awk '{print $3}')
    SPEED_DOWNLOAD_BPS=$(echo "$CURL_OUTPUT" | awk '{print $4}')

    RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc)
    SIZE_MB=$(echo "scale=4; $SIZE_DOWNLOADED / 1048576" | bc)
    SPEED_MBPS=$(echo "scale=4; $SPEED_DOWNLOAD_BPS * 8 / 1000000" | bc)

    STATUS="DOWN"
    if [[ $CURL_EXIT -eq 0 && $HTTP_STATUS -eq 200 ]]; then
        STATUS="UP"
        ((UP_COUNT++))
    else
        ((DOWN_COUNT++))
    fi

    ((TOTAL_RUNS++))
    TOTAL_RESPONSE_TIME=$(echo "$TOTAL_RESPONSE_TIME + $RESPONSE_TIME_MS" | bc)
    TOTAL_BYTES_DOWNLOADED=$(echo "$TOTAL_BYTES_DOWNLOADED + $SIZE_DOWNLOADED" | bc)
    TOTAL_SPEED_MBPS=$(echo "$TOTAL_SPEED_MBPS + $SPEED_MBPS" | bc)

    CMP_MIN=$(echo "$RESPONSE_TIME_MS < $MIN_RESPONSE_TIME" | bc)
    CMP_MAX=$(echo "$RESPONSE_TIME_MS > $MAX_RESPONSE_TIME" | bc)
    if [[ "$CMP_MIN" -eq 1 ]]; then MIN_RESPONSE_TIME=$RESPONSE_TIME_MS; fi
    if [[ "$CMP_MAX" -eq 1 ]]; then MAX_RESPONSE_TIME=$RESPONSE_TIME_MS; fi

    # === NDJSON Log Line ===
    echo "{\"TimeGenerated\":\"$TIMESTAMP\",\"ProxyStatus\":\"$STATUS\",\"HttpStatus\":$HTTP_STATUS,\"ResponseTime_ms\":$RESPONSE_TIME_MS,\"SizeDownloaded_MB\":$SIZE_MB,\"DownloadSpeed_mbps\":$SPEED_MBPS}" >> "$LOG_FILE_JSON"

    # === CSV Log Line (Optional) ===
    # echo "$TIMESTAMP,$STATUS,$HTTP_STATUS,$RESPONSE_TIME_MS,$SIZE_MB,$SPEED_MBPS" >> "$LOG_FILE_CSV"

    sleep $SLEEP_INTERVAL
done

# === FINAL SUMMARY ===
AVG_RESPONSE_TIME=$(echo "scale=2; $TOTAL_RESPONSE_TIME / $TOTAL_RUNS" | bc)
TOTAL_MB=$(echo "scale=2; $TOTAL_BYTES_DOWNLOADED / 1048576" | bc)
AVG_SPEED_MBPS=$(echo "scale=2; $TOTAL_SPEED_MBPS / $TOTAL_RUNS" | bc)

# === PRINT SUMMARY TO SHELL ===
echo ""
echo "Summary:"
echo "TotalRuns,UpCount,DownCount,MinResponseTime_ms,MaxResponseTime_ms,AvgResponseTime_ms,TotalDownloaded_MB,AvgDownloadSpeed_mbps"
echo "$TOTAL_RUNS,$UP_COUNT,$DOWN_COUNT,$MIN_RESPONSE_TIME,$MAX_RESPONSE_TIME,$AVG_RESPONSE_TIME,$TOTAL_MB,$AVG_SPEED_MBPS"
