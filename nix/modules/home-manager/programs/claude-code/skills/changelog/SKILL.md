---
name: changelog
description: Generate a technical report of significant codebase changes from recent commits
disable-model-invocation: true
argument-hint: [days]
---

Generate a technical changelog report for developers wanting to get up to speed with recent codebase changes.

## Parameters

- `$ARGUMENTS`: Number of days to look back (default: 7 if not provided)

## Instructions

1. **Gather commits from the specified time period**:
   ```bash
   git log --since="$ARGUMENTS days ago" --merges --oneline
   ```
   If `$ARGUMENTS` is empty, use 7 days as the default.

2. **For each significant merge commit**, extract:
   - **Commit hash and title**
   - **GitHub PR link**: Parse from commit message or use `gh pr list --search "<commit>" --state merged`
   - **Author**: From git log
   - **Date merged**

3. **Analyze each change to determine**:

   ### Size of Change
   Measure using git stats:
   ```bash
   git show <commit> --stat | tail -1  # e.g., "15 files changed, 423 insertions(+), 89 deletions(-)"
   ```
   Classify into T-shirt sizes based on lines changed (insertions + deletions):
   - **XS** (< 50 lines): Trivial fix, typo, config tweak
   - **S** (50-200 lines): Small bug fix, minor feature, single-file change
   - **M** (200-500 lines): Medium feature, multi-file refactor
   - **L** (500-1500 lines): Large feature, significant refactor, new service component
   - **XL** (> 1500 lines): Major feature, architectural change, new subsystem

   Also note the number of files changed as additional context.

   ### Complexity Assessment
   Rate complexity as **Low**, **Medium**, or **High** based on these factors:

   **Low complexity** (straightforward, easy to review):
   - Single service/entity affected
   - No database migrations
   - No API changes
   - Localized change (few files, single module)
   - Well-understood pattern (e.g., adding a field, new endpoint following existing pattern)

   **Medium complexity** (requires careful review):
   - 2-3 services/entities affected
   - Database migration with simple schema changes
   - New API endpoints or modifications to existing ones
   - Moderate cross-cutting concerns
   - Some business logic changes
   - Changes to shared libraries used by multiple services

   **High complexity** (tricky, needs deep understanding):
   - 4+ services/entities affected
   - Complex database migrations (data transformations, constraint changes)
   - Breaking API changes
   - Core algorithm or business logic changes
   - Concurrency or state management changes
   - Performance-critical code paths
   - Security-sensitive changes (auth, permissions, crypto)
   - Changes to matching engine, risk calculations, or settlement logic
   - Infrastructure changes affecting multiple environments

   Provide a brief rationale for the complexity rating.

   ### Entity Impacted
   Classify based on paths changed:
   - `exchange` - Exchange operations (src/exchange/, trading, matching engine)
   - `clearinghouse` - Clearing operations (src/clearing/, settlement, risk)
   - `fcm` - FCM/Brokerage operations (src/web/frontend/projects/fcm/, clearing member)
   - `infrastructure` - Ops/deployment (ops/, terraform, ansible, nomad)
   - `frontend` - Web UI (src/web/frontend/)
   - `shared` - Core libraries used across entities

   ### Services Impacted
   Identify specific services from changed paths:
   - engine, gateway, risk, pricefeed, event-writer, settlement
   - auth, web services
   - database, API endpoints

   ### Database Schema Changes
   Check for migrations:
   ```bash
   git show <commit> --name-only | grep -E "migrations/|\.sql$"
   ```
   If found, show the migration content and explain:
   - Tables added/modified/removed
   - Columns changed
   - Index changes
   - Data migrations

   ### Infrastructure/Automation Changes
   Check for:
   ```bash
   git show <commit> --name-only | grep -E "ops/|\.tf$|\.yml$|\.yaml$|Dockerfile|nomad|ansible"
   ```
   If found, summarize deployment or CI/CD changes.

4. **Select the Top 3 Must-Know Changes**:

   After analyzing all PRs, select the 3 most important changes a developer must know about. Prioritize based on:

   - **Breaking changes** or API modifications that affect how developers work
   - **New capabilities** that developers should leverage
   - **Bug fixes** for issues developers may have encountered or worked around
   - **Database schema changes** that affect queries or data models
   - **Architectural changes** that affect how code should be structured going forward
   - **Security fixes** that developers need to be aware of
   - **Performance improvements** in hot paths or critical services

   For each pick, write a concise one-sentence summary of why it matters to a developer's day-to-day work.

5. **For each significant feature, document**:

   ### Before
   How the system worked before this change (based on the PR description and code diff).

   ### After
   How the system works after this change, highlighting the new behavior or capability.

## Output Format

Produce a markdown report structured as:

```markdown
# Codebase Changelog: Last N Days

**Period**: YYYY-MM-DD to YYYY-MM-DD
**Total Merged PRs**: X

### At a Glance

| Size | Count |
|------|-------|
| XL   | 1     |
| L    | 2     |
| M    | 5     |
| S    | 3     |
| XS   | 1     |

| Complexity | Count |
|------------|-------|
| High       | 2     |
| Medium     | 4     |
| Low        | 6     |

### Top 3 Must-Know Changes

These are the changes you absolutely need to know about - selected based on impact, complexity, and relevance to day-to-day development.

1. **[PR Title](URL)** - One-sentence summary of why this matters. (Size: L, Complexity: High)
2. **[PR Title](URL)** - One-sentence summary of why this matters. (Size: M, Complexity: Medium)
3. **[PR Title](URL)** - One-sentence summary of why this matters. (Size: M, Complexity: High)

---

## [PR Title](GitHub PR URL)

| Field | Value |
|-------|-------|
| **Commit** | `abc123` |
| **Author** | Name |
| **Merged** | YYYY-MM-DD |
| **Size** | M (12 files, +423/-89) |
| **Complexity** | Medium |
| **Entity** | exchange, fcm |
| **Services** | engine, gateway |
| **DB Changes** | Yes/No |
| **Infra Changes** | Yes/No |

### Summary
Brief description of the change.

### Complexity Rationale
Why this change is rated Low/Medium/High complexity (e.g., "Touches settlement logic and requires coordinated database migration across two services").

### Before
How the system worked previously.

### After
How the system works now.

### Database Changes
(If applicable) Details of schema modifications.

### Infrastructure Changes
(If applicable) Details of deployment/ops modifications.

---

(Repeat for each significant PR)
```

## Guidelines

- Focus on **significant changes** (features, fixes, refactors) - skip minor typos, doc-only changes, or dependency bumps unless they're notable
- Be technical and precise - this is for developers
- Include code references where helpful (file:line format)
- Group related PRs if they're part of the same feature
- **Order PRs by importance**: High complexity first, then by size (XL → XS), then by date
- Use the "At a Glance" summary to help readers quickly assess the volume and nature of changes
- For High complexity changes, be especially thorough in the Before/After and Complexity Rationale sections
