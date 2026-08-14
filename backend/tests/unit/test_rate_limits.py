from __future__ import annotations

import asyncio

from musicflow.security.rate_limits import SlidingWindowRateLimiter


class AdjustableClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def test_sliding_window_rejects_excess_and_recovers() -> None:
    clock = AdjustableClock()
    limiter = SlidingWindowRateLimiter(
        request_limit=2,
        window_seconds=10,
        max_keys=100,
        clock=clock,
    )

    async def scenario() -> None:
        assert (await limiter.consume("user-1")).allowed
        assert (await limiter.consume("user-1")).allowed

        rejected = await limiter.consume("user-1")
        assert not rejected.allowed
        assert rejected.retry_after_seconds == 10

        assert (await limiter.consume("user-2")).allowed
        clock.now = 10
        assert (await limiter.consume("user-1")).allowed

    asyncio.run(scenario())


def test_sliding_window_rejects_invalid_configuration() -> None:
    try:
        SlidingWindowRateLimiter(request_limit=0, window_seconds=60, max_keys=100)
    except ValueError as error:
        assert str(error) == "Rate limit values must be positive."
    else:
        raise AssertionError("invalid rate limit configuration must be rejected")
