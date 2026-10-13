# Upstream supplies compiled React dist/. Produce a same-origin API variant.
ARG PYTHON_IMAGE=python:3.13-slim-bookworm@sha256:a1165e272e578941b84abc79e4ab38a0305cd12803a5c4247979ac7655f4d641
ARG NGINX_IMAGE=nginxinc/nginx-unprivileged:stable-bookworm@sha256:cd33960e98e93d4d63385790ff7f8f5bf2ca95184c581b7f42ae8aea1139fbfc
FROM ${PYTHON_IMAGE} AS prepare
WORKDIR /build
COPY dist/ ./dist/
COPY scripts/prepare-dist.py ./prepare-dist.py
RUN python prepare-dist.py --source dist --output static

# Override NGINX_IMAGE with an approved digest to pin the runtime image.
FROM ${NGINX_IMAGE}

ARG SOURCE_REVISION=unknown
LABEL org.opencontainers.image.title="Brain Tasks" \
      org.opencontainers.image.description="Compiled React application served by unprivileged Nginx on port 3000" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      org.opencontainers.image.source="https://github.com/Vennilavanguvi/Brain-Tasks-App"

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/security-headers.conf /etc/nginx/security-headers.conf
COPY --from=prepare /build/static/ /usr/share/nginx/html/
COPY nginx/entrypoint.sh /entrypoint.sh

USER 101:101
EXPOSE 3000
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:3000/healthz >/dev/null || exit 1
# Bypass the image's config-mutating entrypoint to support a read-only filesystem.
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
