#!/usr/bin/env python3
"""
Generate Windscribe IP address lists for MikroTik RouterOS.

Fetches IP lists from tn3w/Windscribe-IPs and produces a RouterOS .rsc file
with two address lists: windscribe-servers and windscribe-entry.
"""

import sys
import urllib.request
import urllib.error
from typing import List, Set

# Configuration
SOURCE_URLS = {
    "windscribe-servers": "https://raw.githubusercontent.com/tn3w/Windscribe-IPs/refs/heads/master/windscribe_ips.txt",
    "windscribe-entry": "https://raw.githubusercontent.com/tn3w/Windscribe-IPs/refs/heads/master/windscribe_entry_ips.txt",
}

OUTPUT_FILE = "windscribe.rsc"
TEMP_FILE = "windscribe.rsc.tmp"
MIN_IP_COUNT = 50
HTTP_TIMEOUT = 30


def fetch_url(url: str) -> str:
    """Fetch content from URL with timeout and error handling."""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Mozilla/5.0 (compatible; WindscribeIPGenerator/1.0)"},
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as response:
            if response.status != 200:
                raise urllib.error.HTTPError(url, response.status, "HTTP error", response.headers, None)
            content = response.read().decode("utf-8")
            if not content or not content.strip():
                raise ValueError(f"Empty response from {url}")
            return content
    except urllib.error.URLError as e:
        raise RuntimeError(f"Failed to fetch {url}: {e.reason}") from e
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP error fetching {url}: {e.code} {e.reason}") from e


def parse_ips(content: str) -> List[str]:
    """Parse IPv4 addresses from text content, skipping comments and invalid lines."""
    ips: Set[str] = set()
    for line_num, line in enumerate(content.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Validate IPv4 format
        parts = line.split(".")
        if len(parts) != 4:
            print(f"Warning: Skipping invalid IP format on line {line_num}: {line}", file=sys.stderr)
            continue
        try:
            octets = [int(p) for p in parts]
            if all(0 <= o <= 255 for o in octets):
                ips.add(line)
            else:
                print(f"Warning: Skipping invalid octet range on line {line_num}: {line}", file=sys.stderr)
        except ValueError:
            print(f"Warning: Skipping non-numeric octet on line {line_num}: {line}", file=sys.stderr)
    return sorted(ips)


def validate_ip_count(list_name: str, ips: List[str]) -> None:
    """Validate that we have a reasonable number of IPs."""
    count = len(ips)
    if count == 0:
        raise RuntimeError(f"No valid IPs found for {list_name}")
    if count < MIN_IP_COUNT:
        raise RuntimeError(f"Too few IPs for {list_name}: got {count}, expected at least {MIN_IP_COUNT}")
    print(f"  {list_name}: {count} IPs")


def generate_rsc(servers: List[str], entries: List[str]) -> str:
    """Generate RouterOS .rsc content."""
    lines = ["/ip firewall address-list"]
    for ip in servers:
        lines.append(f'add list="windscribe-servers" address="{ip}" comment="Windscribe"')
    for ip in entries:
        lines.append(f'add list="windscribe-entry" address="{ip}" comment="Windscribe"')
    return "\n".join(lines) + "\n"


def main() -> int:
    print("Fetching Windscribe IP lists...")
    all_ips = {}

    for list_name, url in SOURCE_URLS.items():
        print(f"  Fetching {list_name} from {url}")
        try:
            content = fetch_url(url)
            ips = parse_ips(content)
            validate_ip_count(list_name, ips)
            all_ips[list_name] = ips
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1

    print("Generating RSC file...")
    rsc_content = generate_rsc(all_ips["windscribe-servers"], all_ips["windscribe-entry"])

    # Atomic write
    try:
        with open(TEMP_FILE, "w") as f:
            f.write(rsc_content)
        import os
        os.replace(TEMP_FILE, OUTPUT_FILE)
        print(f"Successfully wrote {OUTPUT_FILE}")
    except Exception as e:
        print(f"Error writing output file: {e}", file=sys.stderr)
        # Clean up temp file if it exists
        try:
            os.remove(TEMP_FILE)
        except OSError:
            pass
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())