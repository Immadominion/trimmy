# Fonts

The branded local build uses Dejanire Sans. Its commercial binaries are private and excluded from Git. Run `node tool/prepare-public-assets.mjs` from the root in a public checkout to substitute the bundled Manrope font in the build configuration. Existing licensed local files are left intact.

Manrope, Bricolage Grotesque, Rubik and the retained Fraunces font keep their upstream SIL OFL licence notices. `SOURCES.json` records provenance for the originally acquired families; each family directory contains its own notices. Preserve these when distributing the app.

Public build typography differs from the README's actual-device screenshots. A licence to use a commercial font does not imply permission to redistribute the raw font software.
