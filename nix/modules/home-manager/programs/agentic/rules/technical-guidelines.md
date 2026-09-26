# Technical Guidelines

- When making technical decisions, do not give much weight to development
  cost. Instead, prefer quality, simplicity, robustness, scalability, and long
  term maintainability.
- When doing bug fixes, always start with reproducing the bug in a end-to-end
  test setting as closely aligned with how an end user would interact with it.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, de picky about the UI you see and be
  obsessed with pixel perfection. If something clearly looks off, even if it
  is not directly related to what you are doing, try to get it fixed along
  your work.
- Apply that same high standard to engineering excellence: lint, test
  failures, and test flakiness. If you see one, even if it is not caused by
  what you are working on right now, still get it fixed.

