# Production image for the Trimmy API. The mobile app and the web workspace are
# built and shipped separately; this image serves only the HTTP API.
#
# It also carries infra/migrations and tool/runtime so a release step can apply
# migrations with the very same build that will serve traffic:
#   docker run --rm -e TRIMMY_MIGRATION_DATABASE_URL=... <image> npm run db:migrate
# Migrations need owner credentials, so that variable must never be given to the
# serving container, which uses the restricted PRACTICE_DATABASE_URL instead.
FROM node:24-alpine AS base
# Keep the image's installer and release CLI on the project's pinned npm.
# node:24-alpine currently bundles npm 11, outside this workspace's engines.
RUN npm install --global npm@10.9.8 --ignore-scripts --no-audit --no-fund

FROM base AS build
WORKDIR /app
ENV CI=true NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_FUND=false
# Shared-lockfile WebSocket peers have no Alpine ARM64 prebuild. Keep their
# compiler toolchain in this build stage; the runtime starts again from base.
RUN apk add --no-cache python3 make g++
# Manifests first so dependency installation is cached independently of source.
COPY package.json package-lock.json ./
COPY packages/domain/package.json packages/domain/package.json
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
# Install only the API/domain dependency tree; the browser ships separately.
RUN npm ci --workspace=@trimmy/api --workspace=@trimmy/domain --include-workspace-root
COPY tsconfig.base.json tsconfig.json ./
COPY packages/domain packages/domain
COPY apps/api apps/api
# Carried into the runtime image so a release step can migrate with this build.
COPY infra/migrations infra/migrations
COPY tool/runtime tool/runtime
RUN npm run build:backend && npm prune --omit=dev \
    --workspace=@trimmy/api --workspace=@trimmy/domain --include-workspace-root

FROM base AS runtime
# HOST must be 0.0.0.0 for the container to be reachable; the API defaults to
# loopback, which is correct for a workstation and wrong for a container.
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4100 NPM_CONFIG_UPDATE_NOTIFIER=false
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/package-lock.json ./package-lock.json
COPY --from=build /app/packages/domain/package.json ./packages/domain/package.json
COPY --from=build /app/packages/domain/dist ./packages/domain/dist
COPY --from=build /app/apps/api/package.json ./apps/api/package.json
COPY --from=build /app/apps/api/dist ./apps/api/dist
COPY --from=build /app/infra/migrations ./infra/migrations
COPY --from=build /app/tool/runtime ./tool/runtime
# node:alpine already provides an unprivileged "node" user.
USER node
EXPOSE 4100
# The API answers /health without touching a provider or the database.
# Deliberately liveness, not readiness: a container must not be restarted
# because its database blipped. Point the platform router at /ready instead.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||4100)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "apps/api/dist/index.js"]
