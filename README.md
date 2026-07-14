# Qoder Action

Turn your GitHub repository into an intelligent workspace with **Qoder**. This action seamlessly integrates Qoder's intelligent capabilities into your development workflow, enabling automated code reviews, interactive debugging, and custom autonomous tasks powered by `qodercli`.

## Features

- **🤖 Intelligent Code Reviews**: Automatically analyze Pull Requests for bugs, security vulnerabilities, and code style issues before they merge.
- **💬 Interactive Development**: Collaborate with `@qoder` directly in Issues and Pull Requests to explain code, refactor logic, or generate tests via chat.
- **🧠 Context-Aware**: Inject project-specific knowledge (architecture, conventions) simply by adding an `Agents.md` file to your repository.
- **🐙 Official GitHub Tools**: Uses GitHub's official MCP Server for repository, Issue, and Pull Request operations.
- **🧩 Highly Extensible**: Define custom **Subagents** and **Slash Commands** to create tailored workflows that match your team's unique processes.
- **⚡ Pipeline Ready**: Built for CI/CD with structured stream-json outputs, enabling seamless integration with other tools and scripts.

## Quick Start

> **Tip**: If you have `qodercli` installed locally, you can run **`/setup-github`** in the TUI to guide you through the entire setup.

Get started with Qoder in your repository in just a few minutes:

### 1. Setup Integration & Get Token

1. Go to [https://qoder.com/account/integrations](https://qoder.com/account/integrations).
2. Connect your Qoder account with GitHub and install the **qoderai** GitHub App to your target repository.
3. Generate a new **Personal Access Token**.

### 2. Add it as a GitHub Secret

Store your token as a secret named `QODER_PERSONAL_ACCESS_TOKEN` in your repository:

- Go to your repository's **Settings > Secrets and variables > Actions**.
- Click **New repository secret**.
- Name: `QODER_PERSONAL_ACCESS_TOKEN`
- Value: *Your generated token*

### 3. Select & Install Workflows

Browse the [`examples/`](./examples/) directory to choose a workflow that fits your needs, then copy it to your repository's `.github/workflows/` directory.

| Workflow | Description | Source |
| :--- | :--- | :--- |
| **Code Review** | Automatically analyzes Pull Requests for code quality and security. | [`code-review.yml`](./examples/code-review.yml) |
| **Assistant** | Enables interactive chat (`@qoder`) in Issues and PRs to explain code or fix bugs. | [`assistant.yml`](./examples/assistant.yml) |

> **Note**: These examples are just the beginning. You can craft powerful, custom workflows by combining Qoder's capabilities with your own logic. Contributions of new workflow examples are welcome!

### 4. Try it out!

- **Code Review**: Open a new Pull Request and wait for Qoder's feedback.
- **Assistant**: Comment `@qoder Explain this code` or `@qoder Fix this bug` on any Issue or PR.

The Assistant workflow covers Issue and PR conversation comments through `issue_comment`, plus PR inline review comments through `pull_request_review_comment`. Mentions in the initial Issue or PR body require separate `issues` or `pull_request` triggers and are not enabled by the example workflow.

## Configuration Reference

### Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `prompt` | Instructions for `qodercli` (passed to `-p` flag). | **Yes** | - |
| `trigger_phrase` | For Issue and PR comment events, require this exact phrase before running qodercli. | No | `''` (disabled) |
| `qoder_personal_access_token` | Your Qoder Personal Access Token. | **Yes** | - |
| `flags` | Additional CLI arguments for `qodercli`. | No | `''` |
| `qodercli_version` | Version of `qodercli`. Default version recommended. | No | `0.1.18` |
| `enable_github_mcp` | Enable GitHub's official MCP Server. | No | `true` (effective) |
| `enable_qoder_github_mcp` | Deprecated alias for `enable_github_mcp`; removed in `v1`. | No | - |


### Secrets

| Name | Description | Required |
|------|-------------|----------|
| `QODER_PERSONAL_ACCESS_TOKEN` | Your Qoder Personal Access Token. | **Yes** |

### Outputs

This action provides outputs that can be consumed by subsequent steps in your workflow.

| Name | Description |
|------|-------------|
| `output_file` | Path to a file containing the full `stdout` from `qodercli`. The content is formatted as **stream-json** (line-delimited JSON objects), making it machine-readable for custom post-processing scripts. |
| `error` | Captures the standard error (stderr) output if the execution encounters issues. |

### Authentication

This action uses OpenID Connect (OIDC) to securely authenticate with Qoder services. Ensure your workflow has the `id-token: write` permission.

### Official GitHub MCP Server

The GitHub MCP integration runs the official [`github/github-mcp-server`](https://github.com/github/github-mcp-server) container under the server name `github`. Its tools therefore use the `mcp__github__*` namespace. The default image is release `v1.5.0`, pinned to its immutable multi-platform manifest digest rather than a floating tag.

The launcher includes a narrow stdio compatibility layer for Qoder CLI versions that materialize optional JSON Schema properties with placeholder values. It keeps the official server as the GitHub implementation while normalizing only mutually exclusive comment fields, pending-review creation fields, and invalid review-comment range defaults before forwarding `tools/call`. Reaction-only requests and final review submission fields pass through unchanged.

The enabled GitHub MCP integration requires a Linux runner with the standard `flock` utility so executions sharing a home can coordinate Qoder configuration access, plus a working Docker daemon. If either dependency or the pinned image is unavailable while MCP is enabled, the action fails immediately. Set `enable_github_mcp: false` when the workflow does not need GitHub MCP tools. A disabled run without `flock` executes qodercli directly and leaves MCP configuration untouched; when `flock` is available, disabled runs still serialize with enabled runs and remove the legacy `qoder_github` entry safely.

When neither `GITHUB_TOOLSETS` nor `GITHUB_TOOLS` is configured, the launcher explicitly limits the official server to the writable `context`, `repos`, `issues`, `pull_requests`, and `users` toolsets. This avoids inheriting additional toolsets that a future server release may add to its own defaults. Setting only `GITHUB_TOOLS` preserves the official server's tools-only selection semantics. GitHub App token permissions remain the authorization boundary. Advanced workflows can set these environment variables on the action step:

| Environment variable | Purpose |
|---|---|
| `GITHUB_TOOLSETS` | Select official MCP toolsets. |
| `GITHUB_TOOLS` | Select individual official MCP tools; when set alone, no default toolsets are added. |
| `GITHUB_READ_ONLY` | Set to `1` to disable mutating tools. |
| `GITHUB_LOCKDOWN_MODE` | Set to `1` to restrict untrusted public-repository content. |
| `GITHUB_MCP_SERVER_IMAGE` | Override the pinned container image, for example with a trusted internal mirror. |

The short-lived GitHub App installation token is carried in an action-private environment variable and bridged to `GITHUB_PERSONAL_ACCESS_TOKEN` only inside the official server launcher; it is never written to `~/.qoder.json`. A disabled run does not overwrite a caller-provided `GITHUB_PERSONAL_ACCESS_TOKEN`, so preserved user MCP servers can continue using it. The action keeps the caller's real `HOME` so Docker credentials and unrelated user MCP servers retain their normal paths. While GitHub MCP is enabled, an OS-level lock serializes the setup → qodercli → restore lifecycle for jobs sharing that home, verifies that the lock pathname still identifies the opened lock inode, and lets every lifecycle child that can touch the configuration retain the lock lease if its parent shell is terminated. A permission-restricted journal in `HOME` lets the next run restore the previous user `github` entry after an interrupted cleanup. Recovery only proceeds while the current entry still matches the action's temporary value and `~/.qoder.json` still resolves to the target recorded in the journal; if either changed independently, the action preserves both the current configuration and journal and reports a conflict. Atomic configuration writes follow an existing `~/.qoder.json` symlink and preserve the link itself. The legacy `qoder_github` entry is removed permanently. `GITHUB_HOST` is forwarded automatically for GitHub Enterprise Server and `ghe.com` support.

For compatibility throughout the `v0` series, `enable_qoder_github_mcp` remains available as a deprecated alias. When both enable inputs are set, `enable_github_mcp` takes precedence. In GitHub Actions, the deprecated setup script propagates a legacy `GITHUB_TOKEN` through the runner-managed `GITHUB_ENV` mechanism, then the runtime launcher bridges it to the official server's `GITHUB_PERSONAL_ACCESS_TOKEN`; neither variable is written to the Qoder configuration. Standalone setup scripts refuse to replace an existing `github` MCP entry; only the locked action lifecycle may install a temporary replacement backed by its recovery journal. Explicit prompt references to the old `mcp__qoder_github__*` namespace must migrate to `mcp__github__*`.

## Customization

Beyond standard configuration, you can deeply customize Qoder's behavior and knowledge base.

### Context Injection
Simply add an `Agents.md` file to your repository. Qoder automatically detects and loads this file into its context. Use this to provide:
- Project-specific coding conventions.
- Architectural overviews.
- Domain-specific terminology.
- Guidelines you want Qoder to follow in every interaction.

### Extensions
We encourage customizing Qoder's behavior using **Subagents** and **Slash Commands**. By defining these in your repository's `.qoder/` directory, you can create structured, persona-based workflows tailored to your project's specific needs.

For detailed documentation on creating subagents and commands, please refer to the [Qoder CLI Documentation](https://docs.qoder.com/cli/using-cli#subagent).

## Recipes & Best Practices

Explore our [Recipes Guide](./docs/recipes.md) for a collection of ready-to-use configurations, including advanced filtering, cost optimization, and language customization.

## Contributing

Contributions are welcome! Whether you're fixing a bug, adding a new [workflow example](./examples/), or improving documentation, we'd love to see your PRs.

Please feel free to open an [Issue](../../issues) if you encounter any problems or have feature requests.

## License

This project is licensed under the [MIT License](./LICENSE).
