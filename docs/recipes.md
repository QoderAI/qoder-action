# Recipes & Best Practices

This guide provides ready-to-use "recipes" for common automation scenarios with Qoder Action. Each recipe combines GitHub Actions configuration with `qodercli` settings to solve specific problems efficiently.

- [Review by File Paths](#review-by-file-paths)
- [Review by Author](#review-by-author)
- [Review by Changesize (Credit Saver)](#review-by-changesize-credit-saver)
- [Custom Output Language](#custom-output-language)

---

## Review by File Paths

**Scenario:** You want to focus your AI review credits on critical files (e.g., authentication logic, API routes) and ignore low-risk changes like documentation or UI tweaks.

**Recipe:** Use GitHub's `paths` and `paths-ignore` filters to precisely control when the review triggers.

```yaml
name: Critical Path Review
on:
  pull_request:
    paths:
      - 'src/auth/**'
      - 'api/**'
      - 'config/security.yml'
    paths-ignore:
      - '**/*.md'
      - 'docs/**'

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: QoderAI/qoder-action@v0
        with:
          qoder_personal_access_token: ${{ secrets.QODER_PERSONAL_ACCESS_TOKEN }}
          prompt: |
            /review-pr
            REPO:${{ github.repository }} PR_NUMBER:${{ github.event.pull_request.number }}
            FOCUS: Security vulnerabilities and critical logic errors.
```

---

## Review by Author

**Scenario:** You want to apply different review strategies based on who submitted the PR. For example, you might want to skip AI reviews for senior maintainers to reduce noise, or enforce stricter reviews for new contributors.

**Recipe:** Use `if` conditions in your job definition to filter by user login or association.

```yaml
name: New Contributor Review
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    # Only run if the PR author is NOT a maintainer or owner
    if: github.event.pull_request.author_association != 'OWNER' && github.event.pull_request.author_association != 'MEMBER'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: QoderAI/qoder-action@v0
        with:
          qoder_personal_access_token: ${{ secrets.QODER_PERSONAL_ACCESS_TOKEN }}
          prompt: |
            /review-pr
            REPO:${{ github.repository }} PR_NUMBER:${{ github.event.pull_request.number }}
```

---

## Review by Changesize (Credit Saver)

**Scenario:** Large PRs can consume a significant amount of tokens and credits. To control costs, you may want to skip AI reviews for PRs that exceed a certain size (e.g., massive refactors or lockfile updates).

**Recipe:** Add a step to check the number of changed lines before invoking Qoder.

```yaml
name: Budget-Friendly Review
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }

      - name: Check PR Size
        id: check_size
        run: |
          # Get the number of changed lines (additions + deletions)
          LINES_CHANGED=$(jq .pull_request.additions < $GITHUB_EVENT_PATH)
          echo "Lines changed: $LINES_CHANGED"
          
          # Set a limit (e.g., 500 lines)
          if [ "$LINES_CHANGED" -gt 500 ]; then
            echo "PR is too large for review. Skipping."
            echo "skip=true" >> $GITHUB_OUTPUT
          else
            echo "skip=false" >> $GITHUB_OUTPUT
          fi

      - uses: QoderAI/qoder-action@v0
        if: steps.check_size.outputs.skip == 'false'
        with:
          qoder_personal_access_token: ${{ secrets.QODER_PERSONAL_ACCESS_TOKEN }}
          prompt: |
            /review-pr
            REPO:${{ github.repository }} PR_NUMBER:${{ github.event.pull_request.number }}
```

---

## Custom Output Language

**Scenario:** You want the AI's responses (whether for Code Reviews, Assistant chats, or other tasks) to be in a specific language (e.g., Chinese, Spanish) to match your team's primary language.

**Recipe:** Simply specify the desired output language in the `prompt`.

```yaml
name: Chinese Assistant
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]

jobs:
  qoder-assistant:
    if: "!endsWith(github.event.comment.user.login, '[bot]')"
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: QoderAI/qoder-action@v0
        with:
          qoder_personal_access_token: ${{ secrets.QODER_PERSONAL_ACCESS_TOKEN }}
          trigger_phrase: '@qoder'
          prompt: |
            /assistant
            ... (other args) ...
            OUTPUT_LANGUAGE: Chinese
```
