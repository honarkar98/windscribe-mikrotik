# Windscribe IPs Fetcher for MikroTik RouterOS v7.x
# Fetches Windscribe server IPs and entry IPs from GitHub repo: https://github.com/tn3w/Windscribe-IPs
# Adds them to address lists for firewall filtering/routing
#
# Usage: 
#   1. Copy this file to MikroTik (Files)
#   2. Run: /import file=windscribe-ips-fetch.rsc
#   3. Or schedule: /system/scheduler/add name="windscribe-ips-update" on-event="/import file=windscribe-ips-fetch.rsc" interval=1d start-time=03:00:00

:global windscribeFetchLog do={
    :local msg "$1"
    :local level "$2"
    :if ($level = "") do={ :set level "info" }
    :log $level ("windscribe-fetch: " . $msg)
}

# Configuration
:local serverListUrl "https://raw.githubusercontent.com/tn3w/Windscribe-IPs/master/windscribe_ips.txt"
:local entryListUrl "https://raw.githubusercontent.com/tn3w/Windscribe-IPs/master/windscribe_entry_ips.txt"
:local serverListName "windscribe-servers"
:local entryListName "windscribe-entry"
:local tempFileServer "windscribe_servers.txt"
:local tempFileEntry "windscribe_entry.txt"
:local fetchTimeout 30
:local maxRetries 3

# Function: Fetch file with retry
:global windscribeFetchFile do={
    :local url "$1"
    :local filename "$2"
    :local retry 0
    :local success false
    
    :while ($retry < $maxRetries && !$success) do={
        :set retry ($retry + 1)
        :do {
            /tool/fetch url=$url dst-path=$filename mode=https timeout=$fetchTimeout
            :set success true
            $windscribeFetchLog ("Downloaded $filename (attempt $retry)")
        } on-error={
            $windscribeFetchLog ("Download failed for $filename (attempt $retry): $error") "warning"
            :delay 5
        }
    }
    :return $success
}

# Function: Parse IPs from file and add to address list
:global windscribeParseAndAdd do={
    :local filename "$1"
    :local listName "$2"
    :local added 0
    :local skipped 0
    :local errors 0
    
    :if ([/file find name=$filename] = "") do={
        $windscribeFetchLog ("File $filename not found") "error"
        :return {"added"=0; "skipped"=0; "errors"=1}
    }
    
    :local content [/file get $filename contents]
    :local lines [:toarray $content]
    
    :foreach line in=$lines do={
        :local trimmed [:trim $line]
        # Skip empty lines and comments
        :if ($trimmed = "" || [:pick $trimmed 0 1] = "#") do={
            :set skipped ($skipped + 1)
        } else={
            # Validate IP format (basic check)
            :if ($trimmed ~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$") do={
                :do {
                    /ip/firewall/address-list add list=$listName address=$trimmed comment="windscribe-auto" disabled=no
                    :set added ($added + 1)
                } on-error={
                    # IP might already exist, that's OK
                    :set skipped ($skipped + 1)
                }
            } else={
                :set errors ($errors + 1)
                $windscribeFetchLog ("Invalid IP format: $trimmed") "warning"
            }
        }
    }
    :return {"added"=$added; "skipped"=$skipped; "errors"=$errors}
}

# Main execution
$windscribeFetchLog "Starting Windscribe IP fetch and update"

# Ensure address lists exist
/ip/firewall/address-list
:if ([find list=$serverListName] = "") do={
    add list=$serverListName address=127.0.0.1 comment="placeholder" disabled=yes
    remove [find list=$serverListName address=127.0.0.1]
}
:if ([find list=$entryListName] = "") do={
    add list=$entryListName address=127.0.0.1 comment="placeholder" disabled=yes
    remove [find list=$entryListName address=127.0.0.1]
}

# Fetch server IPs
$windscribeFetchLog "Fetching server IPs from GitHub..."
:local serverFetchOk [$windscribeFetchFile $serverListUrl $tempFileServer]

# Fetch entry IPs
$windscribeFetchLog "Fetching entry IPs from GitHub..."
:local entryFetchOk [$windscribeFetchFile $entryListUrl $tempFileEntry]

# Process server IPs
:local serverResult {"added"=0; "skipped"=0; "errors"=0}
:if ($serverFetchOk) do={
    $windscribeFetchLog "Processing server IPs..."
    :set serverResult [$windscribeParseAndAdd $tempFileServer $serverListName]
} else={
    $windscribeFetchLog "Failed to fetch server IPs after $maxRetries attempts" "error"
}

# Process entry IPs
:local entryResult {"added"=0; "skipped"=0; "errors"=0}
:if ($entryFetchOk) do={
    $windscribeFetchLog "Processing entry IPs..."
    :set entryResult [$windscribeParseAndAdd $tempFileEntry $entryListName]
} else={
    $windscribeFetchLog "Failed to fetch entry IPs after $maxRetries attempts" "error"
}

# Cleanup temp files
:do { /file remove $tempFileServer } on-error={}
:do { /file remove $tempFileEntry } on-error={}

# Summary
:local totalAdded ($serverResult->"added" + $entryResult->"added")
:local totalSkipped ($serverResult->"skipped" + $entryResult->"skipped")
:local totalErrors ($serverResult->"errors" + $entryResult->"errors")

$windscribeFetchLog ("Complete! Server IPs: added=$($serverResult->"added") skipped=$($serverResult->"skipped") | Entry IPs: added=$($entryResult->"added") skipped=$($entryResult->"skipped") | Errors: $totalErrors")

# Print address list counts
:local serverCount [/ip/firewall/address-list print count-only where list=$serverListName]
:local entryCount [/ip/firewall/address-list print count-only where list=$entryListName]
$windscribeFetchLog ("Address list '$serverListName': $serverCount entries")
$windscribeFetchLog ("Address list '$entryListName': $entryCount entries")