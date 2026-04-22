FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables \
    iproute2 \
    kmod \
    procps \
    libnetfilter-queue1 \
    gcc \
    python3-dev \
    libnetfilter-queue-dev \
    && pip install --no-cache-dir NetfilterQueue \
    && apt-get purge -y gcc python3-dev libnetfilter-queue-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.py /entrypoint.py
COPY supervisor.sh /supervisor.sh
RUN chmod +x /entrypoint.py /supervisor.sh

# Supervisor restarts entrypoint.py on crash, forwards SIGTERM cleanly.
ENTRYPOINT ["/supervisor.sh"]
