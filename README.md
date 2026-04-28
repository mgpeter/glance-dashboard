# glance-dashboard

My personal setup for Glance. Decided to wrap my slightly customised Glance dashboard in a Docker container to make it easier to manage and deploy.

## Releasing

Version is tracked in [VERSION](./VERSION). The release scripts bump it, build the image, tag both `latest` and the bumped version, and push to Docker Hub.

```bash
# Bash / Linux / macOS / WSL / Git Bash
./scripts/release.sh --patch     # 1.0.2 -> 1.0.3 (default)
./scripts/release.sh --minor     # 1.0.2 -> 1.1.0
./scripts/release.sh --major     # 1.0.2 -> 2.0.0
./scripts/release.sh --dry-run   # show the bump and exit
./scripts/release.sh --no-push   # build + tag locally, skip push
```

```powershell
# Windows / PowerShell 7+
./scripts/release.ps1 -Patch
./scripts/release.ps1 -Minor
./scripts/release.ps1 -Major
./scripts/release.ps1 -DryRun
./scripts/release.ps1 -NoPush
```

You must be logged into Docker Hub (`docker login`) before pushing. The scripts do not commit the bumped `VERSION` file — commit it manually after a successful release.

## Configuration

Pages live in `glance/config/*.yml` and are wired together by `glance.yml` via `$include`. Each page's widgets are themselves extracted into `glance/config/widgets/`, one widget per file, and pulled in with `- $include: widgets/<name>.yml`. To add a widget to a page, drop a new YAML file into `widgets/` and add an `$include` entry to the relevant page.

## Screens

### Main

![Main Screen](screen-home.png)

### Gaming

![Gaming Screen](screen-gaming.png)

### Markets

![Markets Screen](screen-markets.png)

## TODO

- [ ] Setup Github Actions to build and push to Docker Hub on new releases
- [ ] Review glance community widgets
- [ ] Setup Github PAT and list personal repo links/stats
- [ ] Azure app services stats