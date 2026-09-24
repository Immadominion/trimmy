# The illustrated office, built for the browser.
#
# This is the same experience as the phone app, not the stocks workspace, and it
# is deliberately a separate service from both. Sign-in is absent here rather
# than broken: privy_flutter has no browser support, so this build is guest
# practice. The public market reads still work, because they need no account.
#
# The SDK is cloned at the exact pinned version from .flutter-version. No
# published Flutter image can build this project: the newest stable image tag is
# 3.44.0, whose Dart SDK is 3.12.0, and the project requires ^3.12.2.
FROM debian:bookworm-slim AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install --no-install-recommends -y \
      ca-certificates curl git unzip xz-utils zip libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.44.2
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:/flutter/bin/cache/dart-sdk/bin:${PATH}"
# A container build is not a multi-user checkout; this keeps git from refusing it.
RUN git config --global --add safe.directory /flutter && flutter precache --web && flutter --version

WORKDIR /app
COPY apps/mobile/pubspec.yaml apps/mobile/pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY apps/mobile/ ./
# Public configuration only. No account credential belongs in a browser bundle,
# and sign-in cannot work here in any case.
ARG TRIMMY_STOCK_API_URL=""
RUN flutter build web --release -t lib/design_study.dart \
      --dart-define=TRIMMY_STOCK_API_URL=$TRIMMY_STOCK_API_URL

FROM nginx:1.27-alpine AS runtime
COPY infra/office/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html
ENV PORT=8080
EXPOSE 8080
