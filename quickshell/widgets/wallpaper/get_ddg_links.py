#!/usr/bin/env python3
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

LOG_FILE = "/tmp/qs_python_scraper.log"


def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} - {msg}\n")
    except Exception:
        pass


def main():
    log("=== NEW SEARCH STARTING ===")
    if len(sys.argv) < 2:
        log("ERROR: No query provided.")
        return

    query = sys.argv[1].strip() + " wallpaper"
    log(f"Query: '{query}'")

    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    urllib.request.install_opener(opener)

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.5",
        "Referer": "https://duckduckgo.com/",
    }

    search_url = (
        "https://duckduckgo.com/?q="
        + urllib.parse.quote(query)
        + "&iar=images&iax=images&ia=images"
    )
    vqd = None

    log(f"Fetching VQD token from: {search_url}")
    for i in range(3):
        try:
            req = urllib.request.Request(search_url, headers=headers)
            html = urllib.request.urlopen(req, timeout=10).read().decode("utf-8")
            match = re.search(r"vqd=([0-9a-zA-Z_-]+)", html) or re.search(
                r'vqd[\'"]?\s*:\s*[\'"]?([0-9a-zA-Z_-]+)', html
            )

            if match:
                vqd = match.group(1)
                log(f"Success! Found VQD token: {vqd}")
                break
            else:
                log(f"Attempt {i + 1}: No VQD found in HTML.")
        except Exception as e:
            log(f"Attempt {i + 1} Network Error: {str(e)}")
            time.sleep(1)

    if not vqd:
        log("CRITICAL ERROR: Failed to get VQD token. Exiting.")
        return

    headers["Referer"] = search_url
    headers["Accept"] = "application/json, text/javascript, */*; q=0.01"

    next_url = None
    links_found = 0

    for page in range(5):  # Limit to 5 pages
        log(f"Fetching JSON page {page + 1}...")

        url = (
            "https://duckduckgo.com" + next_url
            if next_url
            else "https://duckduckgo.com/i.js?"
            + urllib.parse.urlencode(
                {
                    "l": "us-en",
                    "o": "json",
                    "q": query,
                    "vqd": vqd,
                    "f": ",,,",
                    "ex": "-1",
                }
            )
        )
        if next_url and "vqd=" not in url:
            url += f"&vqd={vqd}"

        try:
            req = urllib.request.Request(url, headers=headers)
            data = json.loads(
                urllib.request.urlopen(req, timeout=10).read().decode("utf-8")
            )
            results = data.get("results", [])
            log(f"Successfully parsed JSON. Found {len(results)} raw image results.")

            for res in results:
                if (
                    int(res.get("width", 0)) >= 1920
                    and int(res.get("height", 0)) >= 1080
                ):
                    t, i = res.get("thumbnail"), res.get("image")
                    if t and i:
                        try:
                            sys.stdout.write(f"{t}|{i}\n")
                            sys.stdout.flush()
                            links_found += 1
                        except BrokenPipeError:
                            log(
                                "Broken pipe detected. Bash script stopped listening. Exiting cleanly."
                            )
                            os._exit(0)

            next_url = data.get("next")
            if not next_url:
                log("No 'next' URL provided by DDG to continue to the next page.")
                break

        except BrokenPipeError:
            log("Broken pipe detected in outer loop. Exiting cleanly.")
            os._exit(0)
        except Exception as e:
            log(f"Error parsing JSON or fetching page: {str(e)}")
            break

    log(f"=== SEARCH COMPLETE. Total FHD links piped to bash: {links_found} ===")


if __name__ == "__main__":
    try:
        os.remove(LOG_FILE)
    except Exception:
        pass

    try:
        main()
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)
    except KeyboardInterrupt:
        os._exit(1)
    except Exception as e:
        log(f"FATAL UNHANDLED ERROR: {str(e)}")
        os._exit(1)
