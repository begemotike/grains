# Build and run

## Prerequisites

- macOS 15+ (developed on macOS 26), Xcode 27.
- XcodeGen (`brew install xcodegen`).
- Developer ID Application certificate in the login keychain (Debug signs with it too; see Distribution). To build without it, override: `xcodebuild ... CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Automatic`.

## Commands

| Command | Does |
|---|---|
| `make core-test` | `swift test` for the package (fast, headless) |
| `make app-test` | generates the project and runs `GrainsAppTests` |
| `make test` | both |
| `make build` | Debug build into `build/` |
| `make run` | build and launch |
| `make icon` | regenerate `App/Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `scripts/release.sh X.Y.Z [--dry-run]` | release pipeline |

## Development database

`GRAINS_DB_PATH=/tmp/grains-dev.sqlite make run` keeps experiments out of the real database. `grains-mcp` honors the same variable.

## Running the MCP server by hand

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | build/Build/Products/Debug/Grains.app/Contents/MacOS/grains-mcp
```
