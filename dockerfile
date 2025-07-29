# Use official Node.js image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install ALL dependencies (including devDependencies for build)
RUN npm install

# Copy all project files
COPY . .

# Set environment variables
ENV NODE_ENV=production
ENV STRAPI_DISABLE_UPDATE_NOTIFICATION=true

# Create uploads directory
RUN mkdir -p public/uploads && chmod 755 public/uploads

# Expose default Strapi port
EXPOSE 1337

# Run Strapi - it will build on first run if needed
CMD ["npm", "run", "develop"]