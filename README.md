# Extrudle

A small ERP for a plastic sheet/film extrusion plant: production planning, lot-tracked stock, purchasing, production logs and dispatch.

- `PLAN.md` has the build plan, with a checklist of slices.
- `CLAUDE.md` has the stack, domain rules and design rules.

## Running locally

```sh
bin/setup        # installs gems, prepares the SQLite databases, seeds demo users
bin/dev          # Rails + Tailwind watcher on http://localhost:3000
```

Demo users (password `extrudle-demo`): `admin@extrudle.test`, `office@extrudle.test`, `floor@extrudle.test`.

## Tests

```sh
bin/rails test
bin/rails test:system
```

## Deploying

Kamal deploys to a single ARM VPS, with images on GHCR (`config/deploy.yml`). SQLite databases live on the `extrudle_storage` volume. Set the server IP and export `KAMAL_REGISTRY_PASSWORD` before running `bin/kamal setup`.
