FROM node:20-slim
RUN apt-get update && apt-get install -y --no-install-recommends libfontconfig1 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json server.js ./
COPY web ./web
COPY server ./server
RUN chmod +x server/ee2_server.x86_64
ENV EE2_DATA_DIR=/data
EXPOSE 8080
CMD ["node", "server.js"]
