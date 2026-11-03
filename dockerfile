
# syntax=docker/dockerfile:1
#
# GLPI 12.0.0 — production PHP-FPM application image.
# Compatible with the existing Helm chart environment contract,
# provided the GLPI 12 base image preserves the same runtime layout.
#
# Build:
# docker build -f docker/php/Dockerfile.base \
#   -t glpi-base:12.0.0 .
#
# docker build -f docker/php/Dockerfile \
#   --build-arg BASE_IMAGE=glpi-base:12.0.0 \
#   -t YOUR_DOCKERHUB_USERNAME/glpi-php-fpm:12.0.0-custom.1 .

ARG BASE_IMAGE=glpi-base:12.0.0

FROM ${BASE_IMAGE} AS app

LABEL org.opencontainers.image.title="GLPI PHP-FPM (production)" \
      org.opencontainers.image.description="Customized GLPI 12.0.0 on PHP-FPM/Alpine" \
      org.opencontainers.image.version="12.0.0"

ARG GLPI_VERSION=12.0.0

# Defaults — overridden at runtime by Helm ConfigMaps, Secrets,
# or Docker Compose environment configuration.
ENV VERSION=${GLPI_VERSION} \
    GLPI_LANG=en_US \
    CACHE_DSN= \
    MARIADB_HOST=db \
    MARIADB_PORT=3306 \
    MARIADB_DATABASE=glpi \
    MARIADB_USER=glpi \
    MARIADB_PASSWORD=glpi \
    GLPI_CONFIG_DIR=/etc/glpi/config \
    GLPI_VAR_DIR=/var/lib/glpi \
    GLPI_MARKETPLACE_DIR=/var/www/html/marketplace \
    GLPI_DOC_DIR=/var/lib/glpi \
    GLPI_CRON_DIR=/var/lib/glpi/_cron \
    GLPI_DUMP_DIR=/var/lib/glpi/_dumps \
    GLPI_GRAPH_DIR=/var/lib/glpi/_graphs \
    GLPI_LOCK_DIR=/var/lib/glpi/_lock \
    GLPI_LOG_DIR=/var/lib/glpi/_log \
    GLPI_PICTURE_DIR=/var/lib/glpi/_pictures \
    GLPI_PLUGIN_DOC_DIR=/var/lib/glpi/_plugins \
    GLPI_RSS_DIR=/var/lib/glpi/_rss \
    GLPI_SESSION_DIR=/var/lib/glpi/_sessions \
    GLPI_TMP_DIR=/var/lib/glpi/_tmp \
    GLPI_UPLOAD_DIR=/var/lib/glpi/_uploads \
    GLPI_CACHE_DIR=/var/lib/glpi/_cache

WORKDIR /var/www/html

# Copy helper scripts before copying the repository.
COPY docker/php/scripts/glpi-*.sh /usr/local/bin/

# Copy your LOCAL, modified GLPI source.
# Build context must be the root of your cloned repository.
COPY . /var/www/html/

# Remove repository/build metadata and the Docker build files
# from the web application directory.
RUN rm -rf \
        /var/www/html/.git \
        /var/www/html/.github \
        /var/www/html/.gitignore \
        /var/www/html/.dockerignore \
        /var/www/html/docker \
        /var/www/html/tests \
    && chmod +x /usr/local/bin/glpi-*.sh \
    && chown -R www-data:www-data /var/www/html \
    && /usr/local/bin/glpi-verify-dir.sh \
    && rm -f /var/www/html/install/install.php

# Copy custom logo images
COPY custom-modifications/SYNAPSE2_white_100x55.png /var/www/html/public/pics/fd_logo.png
COPY custom-modifications/glpi.png /var/www/html/public/pics/glpi.png
COPY custom-modifications/SYNAPSE2_normal_250x138.png /var/www/html/public/pics/login_logo_glpi.png
COPY custom-modifications/logo-G-100-black.png /var/www/html/public/pics/logos/logo-G-100-black.png
COPY custom-modifications/logo-G-100-grey.png /var/www/html/public/pics/logos/logo-G-100-grey.png
COPY custom-modifications/logo-G-100-white.png /var/www/html/public/pics/logos/logo-G-100-white.png
COPY custom-modifications/SYNAPSE2_normal_100x55.png /var/www/html/public/pics/logos/logo-GLPI-100-black.png
COPY custom-modifications/SYNAPSE2_grey_100x55.png /var/www/html/public/pics/logos/logo-GLPI-100-grey.png
COPY custom-modifications/SYNAPSE2_white_100x55.png /var/www/html/public/pics/logos/logo-GLPI-100-white.png
COPY custom-modifications/SYNAPSE2_normal_250x138.png /var/www/html/public/pics/logos/logo-GLPI-250-black.png
COPY custom-modifications/SYNAPSE2_grey_250x138.png /var/www/html/public/pics/logos/logo-GLPI-250-grey.png
COPY custom-modifications/SYNAPSE2_white_250x138.png /var/www/html/public/pics/logos/logo-GLPI-250-white.png


# The web installer must never be reachable in production.
RUN rm -rf /var/www/html/install/install.php

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD php-fpm -t && \
        php -r "exit(@fsockopen('127.0.0.1', 9000) ? 0 : 1);" || exit 1

EXPOSE 9000/tcp

USER www-data

CMD ["php-fpm"]