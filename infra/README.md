# Database and runtime

Ordered SQL migrations live in `migrations/`. They cover accounts, guests, practice progress, the paper ledger, Career rewards, workdays, social state and provider order records. Database functions and restricted roles enforce the durable state transitions.

## Apply migrations

Use the root `.env.example` for exact environment variable names. The migration process uses a separate privileged connection through `TRIMMY_MIGRATION_DATABASE_URL`; the serving API uses `PRACTICE_DATABASE_URL` for its restricted runtime role. TLS verification is required. The runner checks migration order and checksums, function ownership and role grants.

```bash
npm run db:migrate
```

Do not edit an already-applied migration. Introduce a forward migration, test it against a disposable cluster, and back up any persistent database before applying it. A schema rollback that drops tables would destroy account and game state.

## Isolated verification

Install PostgreSQL binaries locally, or set `TRIMMY_POSTGRES_BIN` to their directory. From the repository root:

```bash
bash infra/tests/run-postgres.sh
npm run test:practice-db
npm run test:migration-db
npm run test:deployment
npm run test:career-reason-sharing-db
```

These harnesses create disposable local clusters under ignored runtime folders. They do not need a production database connection. The migration and deployment harnesses verify TLS and role boundaries as well as schema behavior. Inspect a leftover runtime directory after a killed process before retrying; never indiscriminately delete a running database directory.

`tool/runtime/local-secure-runtime.mjs` additionally manages a developer-owned TLS runtime under private local storage. It requires the developer's own Privy public verifier configuration and is not needed to run isolated tests.

Workday publishing is documented in [content/workdays](../content/workdays/README.md). See [development](../docs/DEVELOPMENT.md) for the complete application setup.
