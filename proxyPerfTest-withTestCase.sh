#!/bin/bash

# === CONFIGURATION ===
PROXY_ADDRESS="http://your.proxy.ip:port"
TARGET_URL="https://www.google.com"
SUMMARY_LOG="/var/log/proxy_summary_log.csv"
RUN_ID=0

# === CSV HEADER ===
if [ ! -f "$SUMMARY_LOG" ]; then
    echo "RunId,DurationSec,SleepTimeSec,TotalRuns,UpCount,DownCount,MinResponseTime_ms,MaxResponseTime_ms,AvgResponseTime_ms,TotalDownloaded_MB,AvgDownloadSpeed_mbps" > "$SUMMARY_LOG"
fi

run_proxy_test() {
    local duration=$1
    local sleep_time=$2
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))

    local total_runs=0
    local up_count=0
    local down_count=0
    local total_response_time=0
    local min_response_time=999999
    local max_response_time=0
    local total_bytes_downloaded=0
    local total_speed_mbps=0

    local iteration_start=$(date +%s)

    while [ $(date +%s) -lt "$end_time" ]; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        remaining=$((end_time - current_time))

        if [ "$total_runs" -gt 0 ]; then
            avg_time_per_run=$(echo "scale=2; $elapsed / $total_runs" | bc)
            est_remaining=$(echo "scale=0; $remaining / 1" | bc)
            eta=$(date -d "$est_remaining seconds" +"%H:%M:%S")
        else
            avg_time_per_run=0
            eta="..."
        fi

        # Display real-time progress
        echo -ne "\r⏳ [$total_runs] Elapsed: ${elapsed}s | ETA: ${remaining}s... " 

        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        output=$(curl -x "$PROXY_ADDRESS" -o /dev/null -s -w "%{http_code} %{time_total} %{size_download} %{speed_download}" --max-time 10 "$TARGET_URL")
        curl_exit=$?

        http_status=$(echo "$output" | awk '{print $1}')
        response_time=$(echo "$output" | awk '{print $2}')
        size_downloaded=$(echo "$output" | awk '{print $3}')
        speed_download=$(echo "$output" | awk '{print $4}')

        response_time_ms=$(echo "$response_time * 1000" | bc)
        size_mb=$(echo "scale=4; $size_downloaded / 1048576" | bc)
        speed_mbps=$(echo "scale=4; $speed_download * 8 / 1000000" | bc)

        if [ "$curl_exit" -eq 0 ] && [ "$http_status" -eq 200 ]; then
            status="UP"
            ((up_count++))
        else
            status="DOWN"
            ((down_count++))
        fi

        total_runs=$((total_runs + 1))
        total_response_time=$(echo "$total_response_time + $response_time_ms" | bc)
        total_bytes_downloaded=$(echo "$total_bytes_downloaded + $size_downloaded" | bc)
        total_speed_mbps=$(echo "$total_speed_mbps + $speed_mbps" | bc)

        # Update min/max
        cmp_min=$(echo "$response_time_ms < $min_response_time" | bc)
        cmp_max=$(echo "$response_time_ms > $max_response_time" | bc)
        if [ "$cmp_min" -eq 1 ]; then min_response_time=$response_time_ms; fi
        if [ "$cmp_max" -eq 1 ]; then max_response_time=$response_time_ms; fi

        sleep "$sleep_time"
    done

    avg_response_time=$(echo "scale=2; $total_response_time / $total_runs" | bc)
    total_mb=$(echo "scale=2; $total_bytes_downloaded / 1048576" | bc)
    avg_speed_mbps=$(echo "scale=2; $total_speed_mbps / $total_runs" | bc)

    # Increment run ID and log result
    RUN_ID=$((RUN_ID + 1))
    echo ""
    echo "✅ Completed RunId: $RUN_ID | Duration: $duration sec | TotalRuns: $total_runs"

    echo "$RUN_ID,$duration,$sleep_time,$total_runs,$up_count,$down_count,$min_response_time,$max_response_time,$avg_response_time,$total_mb,$avg_speed_mbps" >> "$SUMMARY_LOG"
}

# === TEST CASES ===
# Format: repeats duration sleep_time
test_cases=(
  "10 60 1"
  "5 600 5"
  "2 3600 10"
)

# === EXECUTE TEST PLAN ===
for case in "${test_cases[@]}"; do
    read -r repeats duration sleep <<< "$case"
    for ((i = 1; i <= repeats; i++)); do
        echo -e "\n➡️  Running Test Case: Duration=${duration}s, Sleep=${sleep}s (Run $i of $repeats)"
        run_proxy_test "$duration" "$sleep"
    done
done
