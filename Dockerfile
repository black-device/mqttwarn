# Docker build file for mqttwarn.
# Based on https://github.com/pfichtner/docker-mqttwarn.
#
# Invoke like:
#
#   docker build --tag=mqttwarn-local .
#
FROM python:3.11-slim-bullseye

# Install additional requirements
RUN apt-get update && apt-get install --yes git

# Create /etc/mqttwarn
RUN mkdir -p /etc/mqttwarn
WORKDIR /etc/mqttwarn

# Add user "mqttwarn"
RUN groupadd -r mqttwarn && useradd -r -g mqttwarn mqttwarn
RUN chown -R mqttwarn:mqttwarn /etc/mqttwarn

# Install mqttwarn
COPY . /src
RUN pip install versioningit wheel
RUN pip install /src

# Make process run as "mqttwarn" user
USER mqttwarn

# Use configuration file from host
VOLUME ["/etc/mqttwarn"]

# Set default configuration path
ENV MQTTWARNINI="/etc/mqttwarn/mqttwarn.ini"

# Invoke program
CMD mqttwarn
