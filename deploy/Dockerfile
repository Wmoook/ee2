FROM node:20-slim
WORKDIR /app
COPY package.json server.js ./
COPY web ./web
COPY server ./server
ENV EE2_DATA_DIR=/data
EXPOSE 8080
CMD ["node", "server.js"]
