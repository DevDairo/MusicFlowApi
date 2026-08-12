from __future__ import annotations

import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

HTTP_OK = 200


def main() -> int:
    url = os.getenv("MUSICFLOW_API_HEALTH_URL", "http://127.0.0.1:8000/health/ready")
    try:
        with urlopen(url, timeout=2) as response:  # noqa: S310 - fixed internal URL by default
            return 0 if response.status == HTTP_OK else 1
    except HTTPError, URLError, TimeoutError:
        return 1


if __name__ == "__main__":
    sys.exit(main())
