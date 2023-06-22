# syntax=docker/dockerfile:1.4
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# THIS DOCKERFILE IS INTENDED FOR PRODUCTION USE AND DEPLOYMENT.
# NOTE! IT IS ALPHA-QUALITY FOR NOW - WE ARE IN A PROCESS OF TESTING IT
#
#
# This is a multi-segmented image. It actually contains two images:
#
# airflow-build-image  - there all airflow dependencies can be installed (and
#                        built - for those dependencies that require
#                        build essentials). Airflow is installed there with
#                        --user switch so that all the dependencies are
#                        installed to ${HOME}/.local
#
# main                 - this is the actual production image that is much
#                        smaller because it does not contain all the build
#                        essentials. Instead the ${HOME}/.local folder
#                        is copied from the build-image - this way we have
#                        only result of installation and we do not need
#                        all the build essentials. This makes the image
#                        much smaller.
#
# Use the same builder frontend version for everyone
ARG AIRFLOW_EXTRAS="aiobotocore,amazon,async,celery,cncf.kubernetes,dask,docker,elasticsearch,ftp,google,google_auth,grpc,hashicorp,http,ldap,microsoft.azure,mysql,odbc,pandas,postgres,redis,sendgrid,sftp,slack,snowflake,ssh,statsd,virtualenv"
ARG ADDITIONAL_AIRFLOW_EXTRAS=""
ARG ADDITIONAL_PYTHON_DEPS=""

ARG AIRFLOW_HOME=/opt/airflow
ARG AIRFLOW_UID="50000"
ARG AIRFLOW_USER_HOME_DIR=/home/airflow

# latest released version here
ARG AIRFLOW_VERSION="2.6.1"

ARG PYTHON_BASE_IMAGE="python:3.8-slim-bullseye"

ARG AIRFLOW_PIP_VERSION=23.1.2
ARG AIRFLOW_IMAGE_REPOSITORY="https://github.com/apache/airflow"
ARG AIRFLOW_IMAGE_README_URL="https://raw.githubusercontent.com/apache/airflow/main/docs/docker-stack/README.md"

# By default latest released version of airflow is installed (when empty) but this value can be overridden
# and we can install version according to specification (For example ==2.0.2 or <3.0.0).
ARG AIRFLOW_VERSION_SPECIFICATION=""

# By default PIP has progress bar but you can disable it.
ARG PIP_PROGRESS_BAR="on"

##############################################################################################
# This is the script image where we keep all inlined bash scripts needed in other segments
##############################################################################################
FROM scratch as scripts

##############################################################################################
# Please DO NOT modify the inlined scripts manually. The content of those files will be
# replaced by pre-commit automatically from the "scripts/docker/" folder.
# This is done in order to avoid problems with caching and file permissions and in order to
# make the PROD Dockerfile standalone
##############################################################################################

# The content below is automatically copied from scripts/docker/install_os_dependencies.sh
COPY scripts/docker/install_os_dependencies.sh /
# The content below is automatically copied from scripts/docker/install_mysql.sh
COPY scripts/docker/install_mysql.sh /
# The content below is automatically copied from scripts/docker/install_mssql.sh
COPY scripts/docker/install_mssql.sh /
# The content below is automatically copied from scripts/docker/install_postgres.sh
COPY scripts/docker/install_postgres.sh /
# The content below is automatically copied from scripts/docker/install_pip_version.sh
COPY scripts/docker/install_pip_version.sh /
# The content below is automatically copied from scripts/docker/install_airflow_dependencies_from_branch_tip.sh
COPY scripts/docker/install_airflow_dependencies_from_branch_tip.sh /
# The content below is automatically copied from scripts/docker/common.sh
COPY scripts/docker/common.sh /
# The content below is automatically copied from scripts/docker/pip
COPY scripts/docker/pip /
# The content below is automatically copied from scripts/docker/install_from_docker_context_files.sh
COPY scripts/docker/install_from_docker_context_files.sh /
# The content below is automatically copied from scripts/docker/install_airflow.sh
COPY scripts/docker/install_airflow.sh /
# The content below is automatically copied from scripts/docker/install_additional_dependencies.sh
COPY scripts/docker/install_additional_dependencies.sh /
# The content below is automatically copied from scripts/docker/entrypoint_prod.sh
COPY scripts/docker/entrypoint_prod.sh /
# The content below is automatically copied from scripts/docker/clean-logs.sh
COPY scripts/docker/clean-logs.sh /

# The content below is automatically copied from scripts/docker/airflow-scheduler-autorestart.sh
COPY scripts/docker/airflow-scheduler-autorestart.sh /

##############################################################################################
# This is the build image where we build all dependencies
##############################################################################################
FROM ${PYTHON_BASE_IMAGE} as airflow-build-image

# Nolog bash flag is currently ignored - but you can replace it with
# xtrace - to show commands executed)
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-o", "nounset", "-o", "nolog", "-c"]

ARG PYTHON_BASE_IMAGE
ENV PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE} \
    DEBIAN_FRONTEND=noninteractive LANGUAGE=C.UTF-8 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 LC_MESSAGES=C.UTF-8

ARG DEV_APT_DEPS=""
ARG ADDITIONAL_DEV_APT_DEPS=""
ARG DEV_APT_COMMAND=""
ARG ADDITIONAL_DEV_APT_COMMAND=""
ARG ADDITIONAL_DEV_APT_ENV=""

ENV DEV_APT_DEPS=${DEV_APT_DEPS} \
    ADDITIONAL_DEV_APT_DEPS=${ADDITIONAL_DEV_APT_DEPS} \
    DEV_APT_COMMAND=${DEV_APT_COMMAND} \
    ADDITIONAL_DEV_APT_COMMAND=${ADDITIONAL_DEV_APT_COMMAND} \
    ADDITIONAL_DEV_APT_ENV=${ADDITIONAL_DEV_APT_ENV}

COPY --from=scripts install_os_dependencies.sh /scripts/docker/
RUN bash /scripts/docker/install_os_dependencies.sh dev

ARG INSTALL_MYSQL_CLIENT="true"
ARG INSTALL_MSSQL_CLIENT="true"
ARG INSTALL_POSTGRES_CLIENT="true"
ARG AIRFLOW_REPO=apache/airflow
ARG AIRFLOW_BRANCH=main
ARG AIRFLOW_EXTRAS
ARG ADDITIONAL_AIRFLOW_EXTRAS=""
# Allows to override constraints source
ARG CONSTRAINTS_GITHUB_REPOSITORY="apache/airflow"
ARG AIRFLOW_CONSTRAINTS_MODE="constraints"
ARG AIRFLOW_CONSTRAINTS_REFERENCE=""
ARG AIRFLOW_CONSTRAINTS_LOCATION=""
ARG DEFAULT_CONSTRAINTS_BRANCH="constraints-main"
ARG AIRFLOW_PIP_VERSION
# By default PIP has progress bar but you can disable it.
ARG PIP_PROGRESS_BAR
# By default we do not use pre-cached packages, but in CI/Breeze environment we override this to speed up
# builds in case setup.py/setup.cfg changed. This is pure optimisation of CI/Breeze builds.
ARG AIRFLOW_PRE_CACHED_PIP_PACKAGES="false"
# This is airflow version that is put in the label of the image build
ARG AIRFLOW_VERSION
# By default latest released version of airflow is installed (when empty) but this value can be overridden
# and we can install version according to specification (For example ==2.0.2 or <3.0.0).
ARG AIRFLOW_VERSION_SPECIFICATION
# By default we install providers from PyPI but in case of Breeze build we want to install providers
# from local sources without the need of preparing provider packages upfront. This value is
# automatically overridden by Breeze scripts.
ARG INSTALL_PROVIDERS_FROM_SOURCES="false"
# Determines the way airflow is installed. By default we install airflow from PyPI `apache-airflow` package
# But it also can be `.` from local installation or GitHub URL pointing to specific branch or tag
# Of Airflow. Note That for local source installation you need to have local sources of
# Airflow checked out together with the Dockerfile and AIRFLOW_SOURCES_FROM and AIRFLOW_SOURCES_TO
# set to "." and "/opt/airflow" respectively.
ARG AIRFLOW_INSTALLATION_METHOD="apache-airflow"
# By default we do not upgrade to latest dependencies
ARG UPGRADE_TO_NEWER_DEPENDENCIES="false"
# By default we install latest airflow from PyPI so we do not need to copy sources of Airflow
# but in case of breeze/CI builds we use latest sources and we override those
# those SOURCES_FROM/TO with "." and "/opt/airflow" respectively
ARG AIRFLOW_SOURCES_FROM="Dockerfile"
ARG AIRFLOW_SOURCES_TO="/Dockerfile"

# By default we do not install from docker context files but if we decide to install from docker context
# files, we should override those variables to "docker-context-files"
ARG DOCKER_CONTEXT_FILES="Dockerfile"

ARG AIRFLOW_HOME
ARG AIRFLOW_USER_HOME_DIR
ARG AIRFLOW_UID

ENV INSTALL_MYSQL_CLIENT=${INSTALL_MYSQL_CLIENT} \
    INSTALL_MSSQL_CLIENT=${INSTALL_MSSQL_CLIENT} \
    INSTALL_POSTGRES_CLIENT=${INSTALL_POSTGRES_CLIENT}

# Only copy mysql/mssql installation scripts for now - so that changing the other
# scripts which are needed much later will not invalidate the docker layer here
COPY --from=scripts install_mysql.sh install_mssql.sh install_postgres.sh /scripts/docker/

RUN bash /scripts/docker/install_mysql.sh dev && \
    bash /scripts/docker/install_mssql.sh && \
    bash /scripts/docker/install_postgres.sh dev
ENV PATH=${PATH}:/opt/mssql-tools/bin

COPY ${DOCKER_CONTEXT_FILES} /docker-context-files

RUN adduser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password \
       --quiet "airflow" --uid "${AIRFLOW_UID}" --gid "0" --home "${AIRFLOW_USER_HOME_DIR}" && \
    mkdir -p ${AIRFLOW_HOME} && chown -R "airflow:0" "${AIRFLOW_USER_HOME_DIR}" ${AIRFLOW_HOME}

USER airflow

RUN if [[ -f /docker-context-files/pip.conf ]]; then \
        mkdir -p ${AIRFLOW_USER_HOME_DIR}/.config/pip; \
        cp /docker-context-files/pip.conf "${AIRFLOW_USER_HOME_DIR}/.config/pip/pip.conf"; \
    fi; \
    if [[ -f /docker-context-files/.piprc ]]; then \
        cp /docker-context-files/.piprc "${AIRFLOW_USER_HOME_DIR}/.piprc"; \
    fi

# Additional PIP flags passed to all pip install commands except reinstalling pip itself
ARG ADDITIONAL_PIP_INSTALL_FLAGS=""

ENV AIRFLOW_PIP_VERSION=${AIRFLOW_PIP_VERSION} \
    AIRFLOW_PRE_CACHED_PIP_PACKAGES=${AIRFLOW_PRE_CACHED_PIP_PACKAGES} \
    INSTALL_PROVIDERS_FROM_SOURCES=${INSTALL_PROVIDERS_FROM_SOURCES} \
    AIRFLOW_VERSION=${AIRFLOW_VERSION} \
    AIRFLOW_INSTALLATION_METHOD=${AIRFLOW_INSTALLATION_METHOD} \
    AIRFLOW_VERSION_SPECIFICATION=${AIRFLOW_VERSION_SPECIFICATION} \
    AIRFLOW_SOURCES_FROM=${AIRFLOW_SOURCES_FROM} \
    AIRFLOW_SOURCES_TO=${AIRFLOW_SOURCES_TO} \
    AIRFLOW_REPO=${AIRFLOW_REPO} \
    AIRFLOW_BRANCH=${AIRFLOW_BRANCH} \
    AIRFLOW_EXTRAS=${AIRFLOW_EXTRAS}${ADDITIONAL_AIRFLOW_EXTRAS:+,}${ADDITIONAL_AIRFLOW_EXTRAS} \
    CONSTRAINTS_GITHUB_REPOSITORY=${CONSTRAINTS_GITHUB_REPOSITORY} \
    AIRFLOW_CONSTRAINTS_MODE=${AIRFLOW_CONSTRAINTS_MODE} \
    AIRFLOW_CONSTRAINTS_REFERENCE=${AIRFLOW_CONSTRAINTS_REFERENCE} \
    AIRFLOW_CONSTRAINTS_LOCATION=${AIRFLOW_CONSTRAINTS_LOCATION} \
    DEFAULT_CONSTRAINTS_BRANCH=${DEFAULT_CONSTRAINTS_BRANCH} \
    PATH=${PATH}:${AIRFLOW_USER_HOME_DIR}/.local/bin \
    AIRFLOW_PIP_VERSION=${AIRFLOW_PIP_VERSION} \
    PIP_PROGRESS_BAR=${PIP_PROGRESS_BAR} \
    ADDITIONAL_PIP_INSTALL_FLAGS=${ADDITIONAL_PIP_INSTALL_FLAGS} \
    AIRFLOW_USER_HOME_DIR=${AIRFLOW_USER_HOME_DIR} \
    AIRFLOW_HOME=${AIRFLOW_HOME} \
    AIRFLOW_UID=${AIRFLOW_UID} \
    AIRFLOW_INSTALL_EDITABLE_FLAG="" \
    UPGRADE_TO_NEWER_DEPENDENCIES=${UPGRADE_TO_NEWER_DEPENDENCIES} \
    # By default PIP installs everything to ~/.local
    PIP_USER="true"

# Copy all scripts required for installation - changing any of those should lead to
# rebuilding from here
COPY --from=scripts common.sh install_pip_version.sh \
     install_airflow_dependencies_from_branch_tip.sh /scripts/docker/

# We can set this value to true in case we want to install .whl/.tar.gz packages placed in the
# docker-context-files folder. This can be done for both additional packages you want to install
# as well as Airflow and Provider packages (it will be automatically detected if airflow
# is installed from docker-context files rather than from PyPI)
ARG INSTALL_PACKAGES_FROM_CONTEXT="false"

# In case of Production build image segment we want to pre-install main version of airflow
# dependencies from GitHub so that we do not have to always reinstall it from the scratch.
# The Airflow (and providers in case INSTALL_PROVIDERS_FROM_SOURCES is "false")
# are uninstalled, only dependencies remain
# the cache is only used when "upgrade to newer dependencies" is not set to automatically
# account for removed dependencies (we do not install them in the first place) and in case
# INSTALL_PACKAGES_FROM_CONTEXT is not set (because then caching it from main makes no sense).
RUN bash /scripts/docker/install_pip_version.sh; \
    if [[ ${AIRFLOW_PRE_CACHED_PIP_PACKAGES} == "true" && \
        ${INSTALL_PACKAGES_FROM_CONTEXT} == "false" && \
        ${UPGRADE_TO_NEWER_DEPENDENCIES} == "false" ]]; then \
        bash /scripts/docker/install_airflow_dependencies_from_branch_tip.sh; \
    fi

COPY --chown=airflow:0 ${AIRFLOW_SOURCES_FROM} ${AIRFLOW_SOURCES_TO}

# Add extra python dependencies
ARG ADDITIONAL_PYTHON_DEPS=""

# Those are additional constraints that are needed for some extras but we do not want to
# force them on the main Airflow package. Currently we need no extra limits as PIP 23.1+ has much better
# dependency resolution and we do not need to limit the versions of the dependencies
# !!! MAKE SURE YOU SYNCHRONIZE THE LIST BETWEEN: Dockerfile, Dockerfile.ci
ARG EAGER_UPGRADE_ADDITIONAL_REQUIREMENTS=""

ENV ADDITIONAL_PYTHON_DEPS=${ADDITIONAL_PYTHON_DEPS} \
    INSTALL_PACKAGES_FROM_CONTEXT=${INSTALL_PACKAGES_FROM_CONTEXT} \
    EAGER_UPGRADE_ADDITIONAL_REQUIREMENTS=${EAGER_UPGRADE_ADDITIONAL_REQUIREMENTS}

WORKDIR ${AIRFLOW_HOME}

COPY --from=scripts install_from_docker_context_files.sh install_airflow.sh \
     install_additional_dependencies.sh /scripts/docker/

# hadolint ignore=SC2086, SC2010
RUN if [[ ${INSTALL_PACKAGES_FROM_CONTEXT} == "true" ]]; then \
        bash /scripts/docker/install_from_docker_context_files.sh; \
    fi; \
    if ! airflow version 2>/dev/null >/dev/null; then \
        bash /scripts/docker/install_airflow.sh; \
    fi; \
    if [[ -n "${ADDITIONAL_PYTHON_DEPS}" ]]; then \
        bash /scripts/docker/install_additional_dependencies.sh; \
    fi; \
    find "${AIRFLOW_USER_HOME_DIR}/.local/" -name '*.pyc' -print0 | xargs -0 rm -f || true ; \
    find "${AIRFLOW_USER_HOME_DIR}/.local/" -type d -name '__pycache__' -print0 | xargs -0 rm -rf || true ; \
    # make sure that all directories and files in .local are also group accessible
    find "${AIRFLOW_USER_HOME_DIR}/.local" -executable -print0 | xargs --null chmod g+x; \
    find "${AIRFLOW_USER_HOME_DIR}/.local" -print0 | xargs --null chmod g+rw

# In case there is a requirements.txt file in "docker-context-files" it will be installed
# during the build additionally to whatever has been installed so far. It is recommended that
# the requirements.txt contains only dependencies with == version specification
RUN if [[ -f /docker-context-files/requirements.txt ]]; then \
        pip install --no-cache-dir --user -r /docker-context-files/requirements.txt; \
    fi

##############################################################################################
# This is the actual Airflow image - much smaller than the build one. We copy
# installed Airflow and all it's dependencies from the build image to make it smaller.
##############################################################################################
FROM ${PYTHON_BASE_IMAGE} as main

# Nolog bash flag is currently ignored - but you can replace it with other flags (for example
# xtrace - to show commands executed)
SHELL ["/bin/bash", "-o", "pipefail", "-o", "errexit", "-o", "nounset", "-o", "nolog", "-c"]

ARG AIRFLOW_UID

LABEL org.apache.airflow.distro="debian" \
  org.apache.airflow.module="airflow" \
  org.apache.airflow.component="airflow" \
  org.apache.airflow.image="airflow" \
  org.apache.airflow.uid="${AIRFLOW_UID}"

ARG PYTHON_BASE_IMAGE
ARG AIRFLOW_PIP_VERSION

ENV PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE} \
    # Make sure noninteractive debian install is used and language variables set
    DEBIAN_FRONTEND=noninteractive LANGUAGE=C.UTF-8 LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    LC_CTYPE=C.UTF-8 LC_MESSAGES=C.UTF-8 LD_LIBRARY_PATH=/usr/local/lib \
    AIRFLOW_PIP_VERSION=${AIRFLOW_PIP_VERSION}

ARG RUNTIME_APT_DEPS=""
ARG ADDITIONAL_RUNTIME_APT_DEPS=""
ARG RUNTIME_APT_COMMAND="echo"
ARG ADDITIONAL_RUNTIME_APT_COMMAND=""
ARG ADDITIONAL_RUNTIME_APT_ENV=""
ARG INSTALL_MYSQL_CLIENT="true"
ARG INSTALL_MSSQL_CLIENT="true"
ARG INSTALL_POSTGRES_CLIENT="true"

ENV RUNTIME_APT_DEPS=${RUNTIME_APT_DEPS} \
    ADDITIONAL_RUNTIME_APT_DEPS=${ADDITIONAL_RUNTIME_APT_DEPS} \
    RUNTIME_APT_COMMAND=${RUNTIME_APT_COMMAND} \
    ADDITIONAL_RUNTIME_APT_COMMAND=${ADDITIONAL_RUNTIME_APT_COMMAND} \
    INSTALL_MYSQL_CLIENT=${INSTALL_MYSQL_CLIENT} \
    INSTALL_MSSQL_CLIENT=${INSTALL_MSSQL_CLIENT} \
    INSTALL_POSTGRES_CLIENT=${INSTALL_POSTGRES_CLIENT} \
    GUNICORN_CMD_ARGS="--worker-tmp-dir /dev/shm" \
    AIRFLOW_INSTALLATION_METHOD=${AIRFLOW_INSTALLATION_METHOD}

COPY --from=scripts install_os_dependencies.sh /scripts/docker/
RUN bash /scripts/docker/install_os_dependencies.sh runtime

# Having the variable in final image allows to disable providers manager warnings when
# production image is prepared from sources rather than from package
ARG AIRFLOW_INSTALLATION_METHOD="apache-airflow"
ARG AIRFLOW_IMAGE_REPOSITORY
ARG AIRFLOW_IMAGE_README_URL
ARG AIRFLOW_USER_HOME_DIR
ARG AIRFLOW_HOME

# By default PIP installs everything to ~/.local
ENV PATH="${AIRFLOW_USER_HOME_DIR}/.local/bin:${PATH}" \
    AIRFLOW_UID=${AIRFLOW_UID} \
    AIRFLOW_USER_HOME_DIR=${AIRFLOW_USER_HOME_DIR} \
    AIRFLOW_HOME=${AIRFLOW_HOME}

# Only copy mysql/mssql installation scripts for now - so that changing the other
# scripts which are needed much later will not invalidate the docker layer here.
COPY --from=scripts install_mysql.sh install_mssql.sh install_postgres.sh /scripts/docker/
# We run scripts with bash here to make sure we can execute the scripts. Changing to +x might have an
# unexpected result - the cache for Dockerfiles might get invalidated in case the host system
# had different umask set and group x bit was not set. In Azure the bit might be not set at all.
# That also protects against AUFS Docker backend problem where changing the executable bit required sync
RUN bash /scripts/docker/install_mysql.sh prod \
    && bash /scripts/docker/install_mssql.sh \
    && bash /scripts/docker/install_postgres.sh prod \
    && adduser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password \
           --quiet "airflow" --uid "${AIRFLOW_UID}" --gid "0" --home "${AIRFLOW_USER_HOME_DIR}" \
# Make Airflow files belong to the root group and are accessible. This is to accommodate the guidelines from
# OpenShift https://docs.openshift.com/enterprise/3.0/creating_images/guidelines.html
    && mkdir -pv "${AIRFLOW_HOME}" \
    && mkdir -pv "${AIRFLOW_HOME}/dags" \
    && mkdir -pv "${AIRFLOW_HOME}/logs" \
    && chown -R airflow:0 "${AIRFLOW_USER_HOME_DIR}" "${AIRFLOW_HOME}" \
    && chmod -R g+rw "${AIRFLOW_USER_HOME_DIR}" "${AIRFLOW_HOME}" \
    && find "${AIRFLOW_HOME}" -executable -print0 | xargs --null chmod g+x \
    && find "${AIRFLOW_USER_HOME_DIR}" -executable -print0 | xargs --null chmod g+x

COPY --from=airflow-build-image --chown=airflow:0 \
     "${AIRFLOW_USER_HOME_DIR}/.local" "${AIRFLOW_USER_HOME_DIR}/.local"
COPY --from=scripts entrypoint_prod.sh /entrypoint
COPY --from=scripts clean-logs.sh /clean-logs
COPY --from=scripts airflow-scheduler-autorestart.sh /airflow-scheduler-autorestart

# Make /etc/passwd root-group-writeable so that user can be dynamically added by OpenShift
# See https://github.com/apache/airflow/issues/9248
# Set default groups for airflow and root user

RUN chmod a+rx /entrypoint /clean-logs \
    && chmod g=u /etc/passwd \
    && chmod g+w "${AIRFLOW_USER_HOME_DIR}/.local" \
    && usermod -g 0 airflow -G 0

# make sure that the venv is activated for all users
# including plain sudo, sudo with --interactive flag
RUN sed --in-place=.bak "s/secure_path=\"/secure_path=\"\/.venv\/bin:/" /etc/sudoers

ARG AIRFLOW_VERSION

# See https://airflow.apache.org/docs/docker-stack/entrypoint.html#signal-propagation
# to learn more about the way how signals are handled by the image
# Also set airflow as nice PROMPT message.
ENV DUMB_INIT_SETSID="1" \
    PS1="(airflow)" \
    AIRFLOW_VERSION=${AIRFLOW_VERSION} \
    AIRFLOW__CORE__LOAD_EXAMPLES="false" \
    PIP_USER="true" \
    PATH="/root/bin:${PATH}"

# Add protection against running pip as root user
RUN mkdir -pv /root/bin
COPY --from=scripts pip /root/bin/pip
RUN chmod u+x /root/bin/pip

WORKDIR ${AIRFLOW_HOME}

EXPOSE 8080

USER ${AIRFLOW_UID}

# Those should be set and used as late as possible as any change in commit/build otherwise invalidates the
# layers right after
ARG BUILD_ID
ARG COMMIT_SHA
ARG AIRFLOW_IMAGE_REPOSITORY
ARG AIRFLOW_IMAGE_DATE_CREATED

ENV BUILD_ID=${BUILD_ID} COMMIT_SHA=${COMMIT_SHA}

LABEL org.apache.airflow.distro="debian" \
  org.apache.airflow.module="airflow" \
  org.apache.airflow.component="airflow" \
  org.apache.airflow.image="airflow" \
  org.apache.airflow.version="${AIRFLOW_VERSION}" \
  org.apache.airflow.uid="${AIRFLOW_UID}" \
  org.apache.airflow.main-image.build-id="${BUILD_ID}" \
  org.apache.airflow.main-image.commit-sha="${COMMIT_SHA}" \
  org.opencontainers.image.source="${AIRFLOW_IMAGE_REPOSITORY}" \
  org.opencontainers.image.created=${AIRFLOW_IMAGE_DATE_CREATED} \
  org.opencontainers.image.authors="dev@airflow.apache.org" \
  org.opencontainers.image.url="https://airflow.apache.org" \
  org.opencontainers.image.documentation="https://airflow.apache.org/docs/docker-stack/index.html" \
  org.opencontainers.image.version="${AIRFLOW_VERSION}" \
  org.opencontainers.image.revision="${COMMIT_SHA}" \
  org.opencontainers.image.vendor="Apache Software Foundation" \
  org.opencontainers.image.licenses="Apache-2.0" \
  org.opencontainers.image.ref.name="airflow" \
  org.opencontainers.image.title="Production Airflow Image" \
  org.opencontainers.image.description="Reference, production-ready Apache Airflow image"
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint"]
CMD []
