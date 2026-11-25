# Multi-stage, non-root (AGENTS.md rule 6). Tag = short git SHA, set by scripts/stub-image.sh.
FROM node:24.22.3-alpine3.24 AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

FROM node:24.22.3-alpine3.24
ENV NODE_ENV=production PORT=8080
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
# The `node` user (uid 1000) ships with the official image; numeric so runAsNonRoot can verify it.
USER 1000:1000
EXPOSE 8080
CMD ["node", "src/server.js"]
