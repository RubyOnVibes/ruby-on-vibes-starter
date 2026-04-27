# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t my-app .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name my-app my-app

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.3
FROM docker.io/library/node:24.13.0-bullseye-slim AS node

FROM docker.io/library/ruby:${RUBY_VERSION}-bookworm AS base

# Rails app lives here
WORKDIR /rails

# Install base packages + build toolchain for hot gem compilation (retries for flaky networks)
# Build tools enable native gem installation on Fly volumes without rebuilding image
# Covers 95%+ of popular gems: pg, mysql2, nokogiri, ffi, etc.
RUN apt-get update -o Acquire::Retries=5 -qq && \
    apt-get install --no-install-recommends -y \
    curl ca-certificates libjemalloc2 libvips sqlite3 gosu rsync git sudo \
    build-essential pkg-config \
    libssl-dev libyaml-dev libpq-dev default-libmysqlclient-dev libsqlite3-dev \
    libxml2-dev libxslt1-dev zlib1g-dev libffi-dev libreadline-dev libgmp-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -o Acquire::Retries=5 -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config ca-certificates libssl-dev && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Provide Node.js from official image and install Yarn via npm
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    node -v && npm -v && npm install -g yarn@1.22.22 && yarn --version

# Install JS deps first for better layer caching
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production=false

# Install application gems (standard Rails - no gemspec needed)
COPY Gemfile Gemfile.lock ./
RUN bundle config build.openssl --with-openssl-dir=/usr && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Reinstall JS deps now that we have full package.json (handles new deps)
RUN yarn install --frozen-lockfile

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Build Vite assets at root level
RUN yarn vite build

RUN yarn build:islands

# Build SSR bundle for Inertia.js server-side rendering
RUN bin/vite build --ssr

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Pre-build SQLite databases with schema for instant setup on deployed machines
# This eliminates CPU-intensive migration runs on user apps (10-15s → <1s)
# Templates stored in /rails/db/templates/ (canonical Rails location for DB assets)
# NOTE: db:schema:load creates ALL databases (primary, cache, queue) in one command
RUN echo "📋 Pre-building SQLite databases for deployment..." && \
    mkdir -p /rails/db/templates && \
    mkdir -p storage && \
    SECRET_KEY_BASE_DUMMY=1 RAILS_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1 ./bin/rails db:schema:load && \
    echo "✅ Databases created, verifying..." && \
    ls -lh storage/production*.sqlite3

# Sanity-check Zeitwerk autoloads to catch missing files before shipping the image
# CRITICAL: Run with databases still in storage/ because Madmin initializer needs database access during eager load
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails zeitwerk:check

# Move databases to templates and clean up
RUN echo "✅ Moving databases to templates..." && \
    mv storage/production.sqlite3 /rails/db/templates/production.sqlite3 && \
    mv storage/production_cache.sqlite3 /rails/db/templates/production_cache.sqlite3 && \
    mv storage/production_queue.sqlite3 /rails/db/templates/production_queue.sqlite3 && \
    echo "✅ Templates created, verifying..." && \
    ls -lh /rails/db/templates/ && \
    rm -rf storage/*.sqlite3* && \
    echo "✅ Pre-built databases ready (will be copied to volumes on first boot)"




# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    node -v && npm -v && npm install -g yarn@1.22.22 && yarn --version

# Create non-root user for running the app (but don't switch yet)
# Setup scripts need root to fix volume permissions, then drop to rails user
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails /rails && \
    chmod +x /rails/bin/*

# Create secure wrapper script for git operations (path-restricted chown)
# This prevents compromised Rails app from chowning arbitrary system files
RUN echo '#!/bin/bash\n\
# Secure wrapper: Only fix ownership of /mnt/data/ paths\n\
# Prevents compromised Rails app from chowning /etc/shadow, /root/.ssh, etc.\n\
set -e\n\
\n\
# Validate paths exist and are under /mnt/data/\n\
for path in /mnt/data/code /mnt/data/sqlite /mnt/data/bundle; do\n\
  if [[ "$path" != /mnt/data/* ]]; then\n\
    echo "ERROR: Path outside /mnt/data/ not allowed: $path" >&2\n\
    exit 1\n\
  fi\n\
  \n\
  # Only chown if path exists (some may not be mounted yet)\n\
  if [ -e "$path" ]; then\n\
    chown -R rails:rails "$path" 2>/dev/null || true\n\
  fi\n\
done\n\
\n\
exit 0\n' > /usr/local/bin/fix-vibes-ownership && \
    chmod 755 /usr/local/bin/fix-vibes-ownership && \
    echo "rails ALL=(ALL) NOPASSWD: /usr/local/bin/fix-vibes-ownership" > /etc/sudoers.d/rails-vibes && \
    chmod 0440 /etc/sudoers.d/rails-vibes

# NOTE: No USER directive here - scripts run as root, drop to rails via gosu

# Standard Docker entrypoint for volume initialization
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start multi-process server: web (Falcon) + SolidQueue worker + SSR server
# Falcon handles HTTP + async-job inline (fiber concurrency)
# SolidQueue handles background jobs (emails, exports, etc.)
# SSR handles Inertia server-side rendering (localhost:13714)
EXPOSE 3000
CMD ["./bin/vibes-server"]