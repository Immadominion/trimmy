# The separate stocks workspace, built as a static bundle and served by nginx.
#
# This is a different experience from the mobile office, not a port of it, and
# it ships as its own artifact. The API it talks to is chosen at build time,
# because a static bundle has no server to read configuration from.
FROM node:24-alpine AS build
WORKDIR /app
ENV CI=true NPM_CONFIG_UPDATE_NOTIFIER=false NPM_CONFIG_FUND=false
RUN npm install --global npm@10.9.8 --ignore-scripts --no-audit --no-fund
COPY package.json package-lock.json ./
COPY packages/domain/package.json packages/domain/package.json
COPY apps/api/package.json apps/api/package.json
COPY apps/web/package.json apps/web/package.json
RUN npm ci --workspace=@trimmy/web --include-workspace-root
COPY tsconfig.base.json tsconfig.json ./
COPY packages/domain packages/domain
# The workspace resolves @trimmy/domain to its build output, so the shared
# package is compiled before the browser bundle typechecks against it.
RUN npx tsc -b packages/domain
COPY apps/web apps/web
# Public configuration only. No secret is ever baked into a browser bundle.
ARG VITE_TRIMMY_API_URL=""
ARG VITE_TRIMMY_STOCK_API_URL=""
ARG VITE_PRIVY_APP_ID=""
ARG VITE_PRIVY_APP_CLIENT_ID=""
ENV VITE_TRIMMY_API_URL=$VITE_TRIMMY_API_URL \
    VITE_TRIMMY_STOCK_API_URL=$VITE_TRIMMY_STOCK_API_URL \
    VITE_PRIVY_APP_ID=$VITE_PRIVY_APP_ID \
    VITE_PRIVY_APP_CLIENT_ID=$VITE_PRIVY_APP_CLIENT_ID
RUN npm run build --workspace=@trimmy/web

FROM nginx:1.27-alpine AS runtime
# Railway assigns the port at run time, so the listener is templated.
COPY infra/web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/apps/web/dist /usr/share/nginx/html
ENV PORT=8080
EXPOSE 8080
