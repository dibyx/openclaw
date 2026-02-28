1.  **Modify **:
    - In , add a check to verify when is enabled.
    - If is true but the client is NOT local, reject the connection with .
    - This ensures that the dangerous flag only operates on localhost, preventing remote exploitation.

2.  **Verify with Reproduction Test**:
    - Run .
    - Expect the test to FAIL (or rather, the assertion that "Remote client allowed" should now fail, and we should update the test to expect rejection).
    - I will update to assert that remote access is REJECTED even with .

3.  **Run Existing Tests**:
    - Run to ensure no regressions for local connections or other scenarios.

4.  **Pre-commit Steps**:
    - Run and follow them.
    - Run linting/formatting if needed.

5.  **Submit**:
    - Commit changes and submit the PR.
