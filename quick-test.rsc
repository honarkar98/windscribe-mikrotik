# Quick one-liner to test Windscribe IP fetch (paste in terminal)
# Fetches from GitHub repo and adds to address list "windscribe-test"

:do {
    /tool/fetch url="https://raw.githubusercontent.com/tn3w/Windscribe-IPs/master/windscribe_ips.txt" dst-path="ws_test.txt" mode=https timeout=30
    :local content [/file get "ws_test.txt" contents]
    :local lines [:toarray $content]
    :local count 0
    :foreach line in=$lines do={
        :local ip [:trim $line]
        :if ($ip != "" && [:pick $ip 0 1] != "#" && $ip ~ "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$") do={
            :do { /ip/firewall/address-list add list="windscribe-test" address=$ip comment="windscribe-test" disabled=no; :set count ($count + 1) } on-error={}
        }
    }
    /file remove "ws_test.txt"
    :log info ("windscribe-test: Added $count IPs to address list")
    :put "Done! Added $count IPs to windscribe-test"
} on-error={
    :log error ("windscribe-test: Failed - $error")
    :put "Error: $error"
}