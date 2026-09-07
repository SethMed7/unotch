# Static landing page for Railway. The build context is the REPOSITORY ROOT
# because the page consumes brand/tokens.css and brand/logo/*.svg; railway.json
# points Railway at this file. scripts/build-site.sh is the single assembly step
# shared with CI and local preview.
FROM alpine:3.22 AS build
WORKDIR /repo
COPY scripts/build-site.sh scripts/build-site.sh
COPY brand brand
COPY site site
RUN sh scripts/build-site.sh /out

FROM caddy:2.11.4-alpine
COPY site/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /out /srv
EXPOSE 8080
