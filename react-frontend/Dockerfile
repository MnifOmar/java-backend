# Step 1: Build the React app
FROM node:18 AS build

WORKDIR /app

# Copy the package.json and install dependencies
COPY package.json ./
COPY package-lock.json ./
RUN npm install

# Copy the rest of the app's source code
COPY . ./

# Build the React app
RUN npm run build

# Step 2: Serve the app using Nginx
FROM nginx:alpine

# Copy the build from the previous step to Nginx's public folder
COPY --from=build /app/build /usr/share/nginx/html

# Expose the port that Nginx listens to
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
