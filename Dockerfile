FROM almalinux:9

LABEL description="Nominatim geocoder on AlmaLinux 9 with PostgreSQL 17"

# ── System update and EPEL ────────────────────────────────────────────────────
# Note: AlmaLinux 9 uses 'crb' (CodeReady Builder) instead of 'powertools'
RUN dnf -y install epel-release && \
    dnf -y install dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y update

# ── PostgreSQL 17 from PGDG ───────────────────────────────────────────────────
RUN dnf -y install \
      https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf -y install \
      postgresql17-server \
      postgresql17-contrib \
      postgis35_17 \
      postgis35_17-utils

# ── Build tools and Nominatim system dependencies ────────────────────────────
# Notes:
#   - curl omitted: AlmaLinux 9 ships curl-minimal which conflicts with curl
#   - osmium-tool omitted: not available in EPEL 9; Nominatim 4.x uses the
#     'osmium' Python package instead of the CLI tool
RUN dnf -y install \
      gcc gcc-c++ make cmake \
      git wget \
      libicu-devel \
      bzip2 bzip2-devel \
      zlib zlib-devel \
      boost-devel \
      expat-devel \
      lua lua-devel \
      osm2pgsql \
      sudo procps-ng vim which jq

# ── Python 3.11 ───────────────────────────────────────────────────────────────
# The 'osmium' PyPI package requires Python >= 3.10.
# Python 3.11 is available in AlmaLinux 9 AppStream.
# ensurepip bootstraps pip for 3.11 since python3-pip targets the system Python.
RUN dnf -y install python3.11 python3.11-devel && \
    ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
    python3.11 -m ensurepip --upgrade && \
    python3.11 -m pip install --upgrade pip

# ── Nominatim Python dependencies ─────────────────────────────────────────────
# 'osmium' is the correct PyPI package name (not 'pyosmium')
RUN python3.11 -m pip install \
      psycopg2-binary PyICU python-dotenv jinja2 \
      uvicorn falcon osmium \
      nominatim-db==4.5.0 nominatim-api==4.5.0

# ── PHP (optional — for Nominatim legacy web API) ─────────────────────────────
RUN dnf -y install php php-pgsql php-intl php-json php-mbstring

# ── Create nominatim user ─────────────────────────────────────────────────────
RUN useradd -m -s /bin/bash nominatim && \
    echo "nominatim ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── Create data directory ─────────────────────────────────────────────────────
RUN mkdir -p /data && chown nominatim:nominatim /data

# ── Add PostgreSQL 17 binaries to PATH ───────────────────────────────────────
RUN echo 'export PATH=/usr/pgsql-17/bin:$PATH' >> /etc/profile.d/pgsql.sh && \
    echo 'export PATH=/usr/pgsql-17/bin:$PATH' >> /home/nominatim/.bashrc

# ── Create log directory ──────────────────────────────────────────────────────
# NOTE: PostgreSQL initdb and pg_hba.conf/postgresql.conf configuration are
# intentionally NOT done here. They are performed at container startup in
# entrypoint.sh so that initialization runs against the live mounted volume,
# not the image layer. Running initdb during build and then mounting a volume
# over the data directory causes subtle PostgreSQL/PostGIS compatibility issues.
RUN mkdir -p /var/log/postgresql && \
    chown postgres:postgres /var/log/postgresql

WORKDIR /home/nominatim
EXPOSE 5432 8088
CMD ["/bin/bash", "-c", "tail -f /dev/null"]
