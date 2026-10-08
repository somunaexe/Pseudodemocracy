# The Pseudodemocracy server: headless Godot running server/ws_server.gd.
#   docker build -t pseudodemocracy .
#   docker run -p 9080:9080 -v pseudo-rooms:/data pseudodemocracy
# NOT YET TRIED: written from the Godot release layout, check the download name for your version when you first build it.
FROM debian:12-slim
ARG GODOT_VERSION=4.7-stable
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
    && unzip /tmp/godot.zip -d /tmp && mv /tmp/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot && rm /tmp/godot.zip
RUN useradd --create-home --uid 10001 game
WORKDIR /app
COPY project.godot ./
COPY data ./data
COPY scripts ./scripts
COPY server ./server
RUN mkdir /data && chown game /data
USER game
ENV PORT=9080 DATA_DIR=/data
EXPOSE 9080
CMD ["godot", "--headless", "--script", "server/ws_server.gd"]
