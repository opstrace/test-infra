# Pull image for copying avalanche binary into python image below
FROM quay.io/freshtracks.io/avalanche:master-2020-12-28-0c1c64c as avalanche

# Now build our python image with avalanche binary added
FROM library/python:3.9.6-slim
COPY --from=avalanche /bin/avalanche /usr/bin/avalanche
COPY rollout_sleep.py /usr/bin/rollout_sleep.py
RUN chmod +x /usr/bin/rollout_sleep.py
RUN /usr/bin/avalanche --help
