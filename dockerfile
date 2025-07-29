# Use official Node.js image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy all project files
COPY . .

# Set NODE_ENV to production
ENV NODE_ENV=production

# Build the admin panel (only if needed)
RUN npm run build || echo "Build step skipped or failed, continuing..."

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S strapi -u 1001
RUN chown -R strapi:nodejs /app
USER strapi

# Expose default Strapi port
EXPOSE 1337

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:1337/_health || exit 1

# Run Strapi in production mode
CMD ["npm", "run", "start"]