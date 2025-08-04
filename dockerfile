# Use official Node.js image
FROM node:20

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install app dependencies including pg (PostgreSQL driver)
RUN npm install pg && npm install

# Copy all project files
COPY . .

# Build the admin panel (for production)
RUN npm run build

# Hea

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:1337/_health || exit 1

# Expose default Strapi port
EXPOSE 1337

# Run Strapi in production mode
CMD ["npm", "run", "start"]
