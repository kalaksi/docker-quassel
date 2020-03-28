# Copyright (c) 2018 kalaksi@users.noreply.github.com.
# This work is licensed under the terms of the MIT license. For a copy, see <https://opensource.org/licenses/MIT>.

FROM alpine:3.11.5 AS base

LABEL maintainer="kalaksi@users.noreply.github.com"
# Use a custom UID/GID instead of the default system UID which has a greater possibility
# for collisions with the host and other containers.
ENV QUASSEL_UID="62643"
ENV QUASSEL_GID="62643"

# You probably will want to configure some of these variables.
# See: https://manpages.ubuntu.com/manpages/disco/man1/quassel.1.html#environment
ENV QUASSEL_USE_TLS "false"
ENV DB_BACKEND="SQLite"
ENV AUTH_AUTHENTICATOR="Database"
ENV AUTH_LDAP_HOSTNAME="ldap://localhost"
ENV AUTH_LDAP_PORT="389"
ENV AUTH_LDAP_BIND_DN=""
ENV AUTH_LDAP_BIND_PASSWORD=""
ENV AUTH_LDAP_BASE_DN=""
ENV AUTH_LDAP_FILTER=""
ENV AUTH_LDAP_UID_ATTRIBUTE="uid"
ENV DB_PGSQL_USERNAME="quassel"
ENV DB_PGSQL_PASSWORD=""
ENV DB_PGSQL_HOSTNAME="localhost"
ENV DB_PGSQL_PORT="5432"
ENV DB_PGSQL_DATABASE="quassel"

FROM base AS builder
ARG QUASSEL_VERSION="0.13.1"
RUN apk add --no-cache --virtual=build-deps  \
      git \
      gcc \
      g++ \
      qt5-qtbase-dev \
      qt5-qtscript-dev \
      qt5-qttools-dev \
      qt5-qtbase-postgresql \
      qt5-qtbase-sqlite \
      boost-dev \
      cmake \
      make \
      openldap-dev && \
    mkdir /opt/quassel && \
    chown ${QUASSEL_UID}:${QUASSEL_GID} /opt/quassel

# For extra security, not running as root in the building phase either!
USER ${QUASSEL_UID}:${QUASSEL_GID}
RUN cd /tmp && \
    git clone https://github.com/quassel/quassel && \
    cd quassel && \
    git checkout "$QUASSEL_VERSION" && \
    mkdir build && \
    mkdir config sqlite-data && \
    cd build && \
    # Thanks goes out to JustJanne for providing an example of hardening the build!
    # I won't be utilizing all of the possible hardening flags here, though, since that would
    # probably need more extensive testing between releases.
    CXXFLAGS="-D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE -pie" cmake .. \
      -DCMAKE_INSTALL_PREFIX=/opt/quassel \
      -DWANT_CORE=ON \
      -DWANT_QTCLIENT=OFF \
      -DWANT_MONO=OFF \
      -DUSE_QT5=ON \
      -DWITH_KDE=OFF \
      -DWITH_BUNDLED_ICONS=OFF \
      -DWITH_WEBKIT=OFF \
      -DEMBED_DATA=OFF \
      -DCMAKE_BUILD_TYPE=Release && \
    make && \
    make install

# Leverage multi-stage building to remove the building layers and make the final image smaller.
FROM base
RUN apk add --no-cache --virtual=runtime-deps \
      boost \
      libldap \
      qt5-qtbase \
      qt5-qtbase-sqlite \
      qt5-qtbase-postgresql \
      qt5-qtscript \
      qt5-qttools

COPY --from=builder /opt/ /opt/
WORKDIR /opt/quassel
# 10113 is the identd port, you probably want to redirect it to port 113
EXPOSE 4242/tcp 10113/tcp

USER ${QUASSEL_UID}:${QUASSEL_GID}
VOLUME ["/opt/quassel/config", "/opt/quassel/sqlite-data"]
ENTRYPOINT ["/opt/quassel/bin/quasselcore", "--configdir=/opt/quassel/config"]
CMD ["--config-from-environment", "--strict-ident"]

