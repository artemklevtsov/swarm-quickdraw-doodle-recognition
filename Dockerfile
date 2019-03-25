FROM tensorflow/tensorflow:1.12.0-gpu

MAINTAINER Artem Klevtsov <a.a.klevtsov@gmail.com>

SHELL ["/bin/bash", "-c"]

ARG LOCALE="en_US.UTF-8"
ARG APT_PKG="libopencv-dev r-base r-base-dev littler"
ARG R_BIN_PKG="futile.logger checkmate data.table rcpp rapidjsonr dbi keras jsonlite curl digest remotes"
ARG R_SRC_PKG="xtensor RcppThread docopt MonetDBLite"
ARG PY_PIP_PKG="keras"
ARG DIRS="/db /app /app/data /app/models /app/logs"

RUN source /etc/os-release && \
    echo "deb https://cloud.r-project.org/bin/linux/ubuntu ${UBUNTU_CODENAME}-cran35/" > /etc/apt/sources.list.d/cran35.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9 && \
    add-apt-repository -y ppa:marutter/c2d4u3.5 && \
    add-apt-repository -y ppa:timsc/opencv-3.4 && \
    apt-get update && \
    apt-get install -y locales && \
    locale-gen ${LOCALE} && \
    apt-get install -y --no-install-recommends ${APT_PKG} && \
    ln -s /usr/lib/R/site-library/littler/examples/install.r /usr/local/bin/install.r && \
    ln -s /usr/lib/R/site-library/littler/examples/install2.r /usr/local/bin/install2.r && \
    ln -s /usr/lib/R/site-library/littler/examples/installGithub.r /usr/local/bin/installGithub.r && \
    echo 'options(Ncpus = parallel::detectCores())' >> /etc/R/Rprofile.site && \
    echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' >> /etc/R/Rprofile.site && \
    apt-get install -y $(printf "r-cran-%s " ${R_BIN_PKG}) && \
    install.r ${R_SRC_PKG} && \
    pip install ${PY_PIP_PKG} && \
    mkdir -p ${DIRS} && \
    chmod 777 ${DIRS} && \
    rm -rf /tmp/downloaded_packages/ /tmp/*.rds && \
    rm -rf /var/lib/apt/lists/*

COPY utils /app/utils
COPY src /app/src
COPY bin/*.R /app/

ENV DBDIR="/db"
ENV CUDA_HOME="/usr/local/cuda"
ENV PATH="/app:${PATH}"

WORKDIR /app

VOLUME /db
VOLUME /app

CMD bash
