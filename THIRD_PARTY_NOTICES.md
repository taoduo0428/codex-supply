# Third-Party Notices

This repository includes or references third-party components.

## Submodules (optional enhanced modules)

Local directory aliases are intentionally neutral. Source mapping remains explicit for compliance.

| Local path | Upstream project | Upstream URL | License |
| --- | --- | --- | --- |
| `external/modules/mod-a` | superpowers | https://github.com/obra/superpowers | MIT (see upstream `LICENSE`) |
| `external/modules/mod-b` | OpenSpace | https://github.com/HKUDS/OpenSpace | MIT (see upstream `LICENSE`) |
| `external/modules/mod-c` | self-improving-for-codex | https://github.com/cyjjjj-21/self-improving-for-codex | Follow upstream repository license; verify before redistribution if upstream license changes. |
| `external/modules/mod-d` | ProactiveAgent | https://github.com/thunlp/ProactiveAgent | Apache-2.0 (see upstream `LICENSE`) |

## Bundled shared runtime assets

1. `common/claude-code-main/dist/global-plugins/*`
2. `common/claude-code-main/scripts/*`

These files are reused from the source bootstrap project. Keep original attribution and license notice when you sync or redistribute this directory.

## Dependency and license responsibility

- End users are responsible for reviewing all submodule licenses.
- If a submodule license or terms change, update this file before release.
- Do not remove third-party copyright notices from copied code.

## Why source mapping is kept (even with neutral local aliases)

- Keeping explicit upstream source mapping is a compliance choice, not a packaging defect.
- Transparent references make license review, attribution, and security audits tractable for downstream users.
- Renaming local folders does not remove legal obligations; explicit mapping prevents audit ambiguity.

## Public release boundary for this project

- Publish `GitHub上线` as the public repository root.
- Do not publish the local `源码工程` workspace as part of the public bundle.
- Keep `external/*` as submodules and keep this mapping file in sync.
