# Pull in the from the official nginx image.
FROM nginx

# Optionally set a maintainer name to let people know who made this image.
MAINTAINER Charlie McClung <charlie@cmr1.com>

# We'll need curl within the nginx image.
RUN apt-get update && apt-get install -y --no-install-recommends curl \
      && rm -rf /var/lib/apt/lists/*

# ENV NGINX_INSTALL_PATH ${NGINX_INSTALL_PATH:-/etc/nginx}
ENV NGINX_INSTALL_PATH /etc/nginx

# Delete the default welcome to nginx page (if it exists)
RUN [ -d /usr/share/nginx/html ] && rm /usr/share/nginx/html/*

COPY config $NGINX_INSTALL_PATH

COPY docker-entrypoint.sh /

# Allow us to customize the entrypoint of the image.
ENTRYPOINT ["/docker-entrypoint.sh"]

# Start nginx in the foreground to play nicely with Docker.
CMD ["nginx", "-g", "daemon off;"]
