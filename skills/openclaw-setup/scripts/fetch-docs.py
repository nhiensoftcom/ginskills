#!/usr/bin/env python3
"""
fetch-docs.py — Fetch OpenClaw documentation pages and output as markdown.
Usage: python3 fetch-docs.py <page-path>
Example: python3 fetch-docs.py start/getting-started
         python3 fetch-docs.py channels/telegram
         python3 fetch-docs.py index  (fetches llms.txt index)
"""

import sys
import urllib.request
import urllib.error
import json
import re

BASE_URL = "https://docs.openclaw.ai"

def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "openclaw-skill/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            content = resp.read().decode("utf-8")
            content_type = resp.headers.get("Content-Type", "")
            return content, content_type
    except urllib.error.HTTPError as e:
        print(f"[ERROR] HTTP {e.code}: {url}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"[ERROR] URL error: {e.reason}", file=sys.stderr)
        sys.exit(1)

def strip_mdx_components(text: str) -> str:
    """Strip MDX JSX tags like <Info>, <Tip>, <Steps>, etc."""
    text = re.sub(r'</?[A-Z][a-zA-Z]*[^>]*>', '', text)
    return text

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fetch-docs.py <page-path|index>")
        print("Examples:")
        print("  python3 fetch-docs.py index")
        print("  python3 fetch-docs.py start/getting-started")
        print("  python3 fetch-docs.py channels/telegram")
        sys.exit(1)

    path = sys.argv[1]

    if path == "index":
        url = f"{BASE_URL}/llms.txt"
    elif path.endswith(".md"):
        url = f"{BASE_URL}/{path}"
    else:
        # Try .md extension first (direct markdown)
        url = f"{BASE_URL}/{path}.md"

    print(f"# Fetching: {url}\n", file=sys.stderr)
    content, content_type = fetch(url)

    # If markdown/plain — output directly
    if "text/markdown" in content_type or "text/plain" in content_type or path == "index":
        print(content)
        return

    # If HTML, try the .md version
    if "text/html" in content_type and not path.endswith(".md"):
        url_md = f"{BASE_URL}/{path}.md"
        print(f"# Retrying as markdown: {url_md}\n", file=sys.stderr)
        content, content_type = fetch(url_md)
        print(content)
        return

    # Fallback: print raw
    print(content)

if __name__ == "__main__":
    main()
