from __future__ import annotations

import asyncio
import math
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class RateLimitDecision:
    allowed: bool
    retry_after_seconds: int | None = None


class SlidingWindowRateLimiter:
    """Bounded, process-local sliding-window limiter for the single API instance."""

    def __init__(
        self,
        *,
        request_limit: int,
        window_seconds: int,
        max_keys: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if request_limit < 1 or window_seconds < 1 or max_keys < 1:
            raise ValueError("Rate limit values must be positive.")

        self._request_limit = request_limit
        self._window_seconds = window_seconds
        self._max_keys = max_keys
        self._clock = clock
        self._requests: dict[str, deque[float]] = {}
        self._lock = asyncio.Lock()

    async def consume(self, key: str) -> RateLimitDecision:
        async with self._lock:
            now = self._clock()
            bucket = self._requests.get(key)

            if bucket is None:
                self._make_capacity(now)
                bucket = deque()
                self._requests[key] = bucket

            self._discard_outside_window(bucket, now)
            if len(bucket) >= self._request_limit:
                retry_after = max(
                    1,
                    math.ceil(bucket[0] + self._window_seconds - now),
                )
                return RateLimitDecision(
                    allowed=False,
                    retry_after_seconds=retry_after,
                )

            bucket.append(now)
            return RateLimitDecision(allowed=True)

    def _make_capacity(self, now: float) -> None:
        if len(self._requests) < self._max_keys:
            return

        expired_keys: list[str] = []
        for key, bucket in self._requests.items():
            self._discard_outside_window(bucket, now)
            if not bucket:
                expired_keys.append(key)

        for key in expired_keys:
            del self._requests[key]

        if len(self._requests) >= self._max_keys:
            oldest_key = min(self._requests, key=lambda key: self._requests[key][-1])
            del self._requests[oldest_key]

    def _discard_outside_window(self, bucket: deque[float], now: float) -> None:
        cutoff = now - self._window_seconds
        while bucket and bucket[0] <= cutoff:
            bucket.popleft()
