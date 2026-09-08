# Use Node.js 16 as required by the assessment.
FROM node:16-bullseye-slim AS dependencies

WORKDIR /app

# Install only production dependencies.
COPY package*.json ./
RUN npm ci --omit=dev \
    && npm cache clean --force


# Create the smaller runtime image.
FROM node:16-bullseye-slim AS runtime

ENV NODE_ENV=production
WORKDIR /app

COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node app.js ./

# The application must not run as root.
USER node

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "const http=require('http');const req=http.get('http://127.0.0.1:8080/',res=>process.exit(res.statusCode===200?0:1));req.on('error',()=>process.exit(1));"

CMD ["node", "app.js"]
