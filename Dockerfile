# Pxxl.app deployment - Next.js Application (Root Structure)
FROM node:18-alpine

# Install curl for health checks
RUN apk add --no-cache curl

# Create app user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Set working directory
WORKDIR /app

# Copy package files and configuration
COPY package*.json ./
COPY next.config.js ./
COPY tailwind.config.js ./
COPY postcss.config.js ./

# Install dependencies
RUN npm ci --only=production

# Copy application source, pages, and public files
COPY app/ ./app/
COPY pages/ ./pages/
COPY public/ ./public/

# Build the Next.js application
RUN npm run build

# Switch to non-root user
USER nextjs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

# Start the Next.js application (standalone mode)
CMD ["node", ".next/standalone/server.js"]
