# Persona: Daniel – Developer

**Role:** Solo developer / small team member using Claude Code daily for greenfield and maintenance work
**Goal:** Use Claude Code productively for complex tasks (refactoring, debugging, code generation) without worrying about accidental file deletions outside the project, unexpected API calls, or credential leaks
**Context:** Works on Linux, has Docker installed, uses multiple projects simultaneously. Wants to `claudius ~/my-project` and have it "just work" with safe defaults.
**Pain Points:**
- Worried that Claude might read `~/.aws` or `~/.ssh` and leak credentials via network calls
- Has had incidents with AI agents running `rm -rf` or making unexpected HTTP requests
- Doesn't want a complex security setup — no YAML configs, no Kubernetes, no learning curve
**Tech Level:** Expert
