FROM rocker/r-ver:4.5.2@sha256:fd4ccdd3a4a6f7ef805e2daeee2a0fe3bf126bc231f36351223baecf5a595a4c

ARG VERSION
ARG VCS_REF
ARG BUILD_DATE

LABEL org.opencontainers.image.title="Paper Monitor" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="LicenseRef-PaperMonitor-Internal"

RUN apt-get update \
    && apt-get full-upgrade -y \
    && apt-get install -y --no-install-recommends \
        curl \
        g++ \
        libcurl4-openssl-dev \
        linux-libc-dev \
        libssl-dev \
        libxml2-dev \
        make \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY DESCRIPTION renv.lock ./

RUN R -q -e "install.packages('https://cran.r-project.org/src/contrib/Archive/renv/renv_1.2.4.tar.gz', repos = NULL, type = 'source')" \
    && R -q -e "renv::restore(prompt = FALSE)"

COPY Paper_Monitor.R ./
COPY R ./R
COPY resources ./resources
COPY config/template.md ./config/template.md

RUN mkdir -p /app/config /app/data /app/output

CMD ["Rscript", "Paper_Monitor.R", "--run"]
