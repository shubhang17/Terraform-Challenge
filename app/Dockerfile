# Mock application image for the CyberEd multi-tenant lab.
#
# Base: tsl0922/ttyd:alpine — a lightweight, browser-accessible terminal.
# Chosen over the literally-named kasmweb/desktop (a full XFCE
# desktop-in-browser image) as the permitted "terminal-based equivalent."
# See docs/DECISIONS.md for the full rationale (cost, cold-start speed,
# and fit for a cybersecurity CLI lab).
#
# This image is built once and promoted (tagged + pushed) into each
# student's own private ECR repository by the registry module -- see
# modules/registry.
FROM tsl0922/ttyd:alpine

# redis-cli is used by entrypoint.sh to register a heartbeat key against
# the centralized cache layer; nc (netcat) ships with busybox/alpine and is
# used to defensively wait for the cache to accept connections before the
# application ever starts (race-condition protection requirement).
RUN apk add --no-cache redis bash

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 7681

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
