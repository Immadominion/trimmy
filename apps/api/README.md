# Trimmy API

Fastify/TypeScript API for accounts, paper trading, market data, Career workdays, wallet reads and gated provider integrations. PostgreSQL owns durable game and order state.

From the repository root:

```bash
npm ci
npm run dev:api
```

The default port is 4100. External integrations and persistent authenticated gameplay need explicit configuration. See [.env.example](../../.env.example), the [development guide](../../docs/DEVELOPMENT.md), [architecture](../../docs/ARCHITECTURE.md) and [database guide](../../infra/README.md).

The API does not load `.env` automatically. After `npm run build:backend`, use `node --env-file=.env apps/api/dist/index.js` from the root when testing your own environment. Never commit provider credentials or point isolated test harnesses at live data.
