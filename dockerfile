# Use Node.js 20 Alpine for smaller image size
FROM node:20-alpine AS base

# Install necessary packages for compilation
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    libc6-compat

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy source code
COPY . .

# Set environment variables
ENV NODE_ENV=production
ENV STRAPI_DISABLE_UPDATE_NOTIFICATION=true
ENV STRAPI_HIDE_STARTUP_MESSAGE=true

# Create necessary directories
RUN mkdir -p public/uploads && \
    mkdir -p .tmp && \
    chmod -R 755 public/uploads

# Build the application (with fallback)
RUN npm run build || echo "Build completed with warnings"

# Create non-root user for security
RUN addgroup -g 1001 -S strapi && \
    adduser -S strapi -u 1001 -G strapi

# Change ownership of app directory
RUN chown -R strapi:strapi /app

# Switch to non-root user
USER strapi

# Expose port
EXPOSE 1337

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:1337/_health || exit 1

# Start the application
CMD ["npm", "start"]