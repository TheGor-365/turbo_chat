# Syntax kept portable for Docker and Railway's Dockerfile builder.
# Production candidate only: deployment requires isolated DB, Redis, private
# mounted storage and completed release acceptance. Never use compose dev creds.
FROM node:24-bookworm-slim AS node
FROM ruby:3.4.12-bookworm AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git pkg-config libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && npm install --global yarn@1.22.22

WORKDIR /app
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn build && yarn build:css

# Compile immutable assets only, never migrate or write to a real database.
# This path exists only in the throwaway build layer, not the runtime image.
RUN mkdir -p /data/build-assets-only \
    && RAILS_ENV=production \
       REDIS_URL=redis://127.0.0.1:6379/0 \
       TURBO_CHAT_STORAGE_ROOT=/data/build-assets-only \
       SECRET_KEY_BASE_DUMMY=1 \
       bin/rails assets:precompile \
    && rm -rf node_modules tmp/cache

FROM ruby:3.4.12-bookworm AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    gosu libpq5 libvips42 imagemagick ffmpeg \
    && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development:test \
    RAILS_LOG_TO_STDOUT=1 RAILS_SERVE_STATIC_FILES=1
WORKDIR /app
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

# Mount ownership is fixed only on an explicitly verified Railway runtime
# volume, then Puma runs without root privileges.
RUN groupadd --gid 1000 rails \
    && useradd --uid 1000 --gid rails --home-dir /app --no-create-home rails \
    && mkdir -p /app/tmp/pids /app/tmp/cache /app/log \
    && chmod 0755 /app/bin/production_entrypoint \
    && chown -R rails:rails /app

EXPOSE 3000
ENTRYPOINT ["/app/bin/production_entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
