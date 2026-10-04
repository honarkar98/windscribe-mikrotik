# Windscribe Direct API Fetcher for MikroTik RouterOS v7.x
# Fetches Windscribe server IPs directly from Windscribe's public mob-v2 API
# Based on: https://github.com/tn3w/Windscribe-IPs
#
# API Endpoints used:
#   https://assets.windscribe.com/serverlist/mob-v2/0/{timestamp}
#   https://assets.windscribe.com/serverlist/mob-v2/1/{timestamp}
#
# Usage: 
#   1. Copy this file to MikroTik (Files)
#   2. Run: /import file=windscribe-api-fetch.rsc
#   3. Or schedule: /system/scheduler/add name="windscribe-api-update" on-event="/import file=windscribe-api-fetch.rsc" interval=1d start-time=03:00:00

:global windscribeApiLog do={
    :local msg "$1"
    :local level "$2"
    :if ($level = "") do={ :set level "info" }
    :log $level ("windscribe-api: " . $msg)
}

# Configuration
:local baseUrl "https://assets.windscribe.com/serverlist/mob-v2"
:local listName "windscribe-servers"
:local tempFile "windscribe_api.json"
:local fetchTimeout 30
:local maxRetries 3

# Function: Fetch with retry
:global windscribeApiFetch do={
    :local url "$1"
    :local filename "$2"
    :local retry 0
    :local success false
    
    :while ($retry < $maxRetries && !$success) do={
        :set retry ($retry + 1)
        :do {
            /tool/fetch url=$url dst-path=$filename mode=https timeout=$fetchTimeout
            :set success true
            $windscribeApiLog ("Downloaded $filename (attempt $retry)")
        } on-error={
            $windscribeApiLog ("Download failed (attempt $retry): $error") "warning"
            :delay 5
        }
    }
    :return $success
}

# Function: Extract IPs from JSON and add to address list
:global windscribeApiProcessJson do={
    :local filename "$1"
    :local listName "$2"
    :local added 0
    :local skipped 0
    :local errors 0
    
    :if ([/file find name=$filename] = "") do={
        $windscribeApiLog ("File $filename not found") "error"
        :return {"added"=0; "skipped"=0; "errors"=1}
    }
    
    :local content [/file get $filename contents]
    
    # Parse JSON - extract all IP fields from nodes and groups
    # The JSON structure has: nodes[].ip, nodes[].ip2-ip5, nodes[].ping_ip, groups[].ip, etc.
    
    # Simple regex extraction for IPv4 addresses from JSON
    :local ipRegex "([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})"
    :local matches [:find $content $ipRegex]
    
    # Since RouterOS doesn't have built-in regex find all, we'll use a different approach
    # Split by common delimiters and validate each potential IP
    :local parts [:toarray $content]
    :local seenIps {}
    
    :foreach part in=$parts do={
        :local candidates [:toarray $part]
        :foreach candidate in=$candidates do={
            :local trimmed [:trim $candidate]
            :if ($trimmed ~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$") do={
                # Validate octets are 0-255
                :local octets [:toarray $trimmed]
                :local valid true
                :foreach octet in=$octets do={
                    :if ($octet < 0 || $octet > 255) do={ :set valid false }
                }
                :if ($valid && !($trimmed in $seenIps)) do={
                    :set seenIps ($seenIps, $trimmed)
                    :do {
                        /ip/firewall/address-list add list=$listName address=$trimmed comment="windscribe-api" disabled=no
                        :set added ($added + 1)
                    } on-error={
                        :set skipped ($skipped + 1)
                    }
                } else={
                    :set skipped ($skipped + 1)
                }
            }
        }
    }
    
    :return {"added"=$added; "skipped"=$skipped; "errors"=$errors}
}

# Main execution
$windscribeApiLog "Starting Windscribe direct API fetch"

# Generate timestamp for API (current unix timestamp)
:local timestamp [/system/clock/get unix-time]

# Ensure address list exists
/ip/firewall/address-list
:if ([find list=$listName] = "") do={
    add list=$listName address=127.0.0.1 comment="placeholder" disabled=yes
    remove [find list=$listName address=127.0.0.1]
}

# Fetch from both endpoints (0 and 1)
:local endpoints {"0"; "1"}
:local totalAdded 0
:local totalSkipped 0
:local totalErrors 0

:foreach endpoint in=$endpoints do={
    :local url "$baseUrl/$endpoint/$timestamp"
    $windscribeApiLog "Fetching from endpoint $endpoint..."
    
    :local fetchOk [$windscribeApiFetch $url $tempFile]
    
    :if ($fetchOk) do={
        $windscribeApiLog "Processing endpoint $endpoint data..."
        :local result [$windscribeApiProcessJson $tempFile $listName]
        :set totalAdded ($totalAdded + $result->"added")
        :set totalSkipped ($totalSkipped + $result->"skipped")
        :set totalErrors ($totalErrors + $result->"errors")
    } else={
        $windscribeApiLog "Failed to fetch endpoint $endpoint after $maxRetries attempts" "error"
        :set totalErrors ($totalErrors + 1)
    }
    
    # Cleanup temp file
    :do { /file remove $tempFile } on-error={}
    :delay 2
}

# Summary
$windscribeApiLog ("Complete! Added: $totalAdded, Skipped: $totalSkipped, Errors: $totalErrors")

# Print address list count
:local listCount [/ip/firewall/address-list print count-only where list=$listName]
$windscribeApiLog ("Address list '$listName': $listCount entries")