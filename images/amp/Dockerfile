# Community packaging; CubeCoders does not support running the ADS controller
# in a container. Pin the dependency image; AMP manages its own runtime updates.
FROM mitchtalmadge/amp-dockerized:v27@sha256:47ecc0346799225c03d95c5cea7b44755de1e1beae382e36d2b7fa3a7e6c4737

# The upstream entrypoint creates this user as root on every boot. Create it
# at build time instead so the entire Kubernetes workload can be non-root.
RUN apt-get update && apt-get install --yes --no-install-recommends tini=0.19.0-3+b8 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1000 amp && useradd --uid 1000 --gid amp --create-home --shell /bin/bash amp
COPY entrypoint.py /opt/homelab/
ENV HOME=/home/amp JAVA_HOME=/usr/lib/jvm/temurin-25-jdk-amd64
USER 1000:1000
WORKDIR /home/amp
# AMP detaches through tmux. Reap those orphaned children so the manager can
# detect exited instances, and forward SIGTERM only to our graceful supervisor.
ENTRYPOINT ["/usr/bin/tini", "--", "python3", "-u", "/opt/homelab/entrypoint.py"]
