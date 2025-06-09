import os
import datetime
import json
import requests
import hashlib
import hmac
import base64
import logging
import azure.functions as func

workspace_id = os.environ['LOG_ANALYTICS_WORKSPACE_ID']
shared_key = os.environ['LOG_ANALYTICS_SHARED_KEY']
log_type = "ProxyMonitoring"
proxy_url = os.environ.get('PROXY_URL', None)

target_urls = [
    "https://www.google.com",
    "https://www.microsoft.com",
    "https://www.github.com",
    "https://www.stackoverflow.com",
    "https://www.bing.com"
]

def build_signature(workspace_id, shared_key, date, content_length, method, content_type, resource):
    x_headers = 'x-ms-date:' + date
    string_to_hash = f"{method}\n{str(content_length)}\n{content_type}\n{x_headers}\n{resource}"
    bytes_to_hash = bytes(string_to_hash, encoding="utf-8")
    decoded_key = base64.b64decode(shared_key)
    encoded_hash = base64.b64encode(hmac.new(decoded_key, bytes_to_hash, digestmod=hashlib.sha256).digest()).decode()
    authorization = f"SharedKey {workspace_id}:{encoded_hash}"
    return authorization

def send_log_entry(log_entry):
    body = json.dumps(log_entry)
    method = 'POST'
    content_type = 'application/json'
    resource = '/api/logs'
    rfc1123date = datetime.datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S GMT')
    content_length = len(body)
    signature = build_signature(workspace_id, shared_key, rfc1123date, content_length, method, content_type, resource)
    uri = f"https://{workspace_id}.ods.opinsights.azure.com{resource}?api-version=2016-04-01"
    headers = {
        'Content-Type': content_type,
        'Authorization': signature,
        'Log-Type': log_type,
        'x-ms-date': rfc1123date
    }
    response = requests.post(uri, data=body, headers=headers)
    if response.status_code >= 200 and response.status_code < 300:
        logging.info(f"Log entry sent: {log_entry}")
    else:
        logging.error(f"Failed to send log entry: {response.status_code} {response.text}")

def main(timer: func.TimerRequest) -> None:
    for url in target_urls:
        timestamp = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
        executed_at = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        status = "Failure"
        status_code = 0
        response_time_ms = 0

        try:
            proxies = {'http': proxy_url, 'https': proxy_url} if proxy_url else None
            start = datetime.datetime.now()
            response = requests.get(url, proxies=proxies, timeout=10)
            end = datetime.datetime.now()
            response_time_ms = round((end - start).total_seconds() * 1000, 3)
            status_code = response.status_code
            status = "Success" if response.status_code == 200 else "Failure"
        except Exception as e:
            logging.error(f"Request failed for {url}: {e}")

        log_entry = {
            "TimeGenerated": timestamp,
            "TargetUrl": url,
            "HttpStatus": status_code,
            "ProxyStatus": status,
            "ResponseTime_ms": response_time_ms,
            "ExecutedAt": executed_at
        }
        send_log_entry(log_entry)
