FROM node:22-alpine
RUN apk add --no-cache git
WORKDIR /app
COPY package.json server.js ./
ENV NODE_ENV=production
CMD ["node", "server.js"]
