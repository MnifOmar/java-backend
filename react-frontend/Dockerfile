# Step 1: Build the React app
FROM node:18 AS build

# Définit le répertoire de travail à /app dans le conteneur
WORKDIR /app

# Copie le fichier package.json et package-lock.json pour installer les dépendances
COPY package.json ./
COPY package-lock.json ./

# Installe les dépendances définies dans package.json
RUN npm install

# Copie l'ensemble des fichiers du projet dans le répertoire de travail du conteneur
COPY . ./

# Lance la commande pour construire l'application (génère les fichiers statiques dans le dossier build)
RUN npm run build

# Utilise l'image légère d'Nginx comme base pour le serveur web
FROM nginx:alpine

# Copie les fichiers statiques générés dans la phase de build vers le répertoire d'Nginx
COPY --from=build /app/build /usr/share/nginx/html

# Expose le port 80 pour permettre l'accès à l'application via HTTP
EXPOSE 80

# Définit la commande par défaut pour démarrer Nginx en mode non-démon
CMD ["nginx", "-g", "daemon off;"]
