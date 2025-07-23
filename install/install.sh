#!/bin/bash

# Installation simplifiée depuis GitHub pour Debian 12
# Utilise directement les fichiers du repository

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Vérifier si root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Ce script doit être exécuté en tant que root${NC}"
   echo "Utilisez: sudo $0"
   exit 1
fi

clear
echo -e "${GREEN}=== Installation YouTube Library depuis GitHub ===${NC}"
echo -e "${BLUE}Repository: https://github.com/Reaper-Official/youtu-selfhost${NC}"
echo ""

# 1. Mise à jour système
echo -e "${YELLOW}📦 Mise à jour du système...${NC}"
apt update && apt upgrade -y

# 2. Installation des dépendances
echo -e "\n${YELLOW}🔧 Installation des dépendances...${NC}"
apt install -y \
    git curl wget build-essential screen \
    python3 python3-pip python3-venv python3-full \
    ffmpeg pipx

# 3. Installation de Node.js 18
echo -e "\n${YELLOW}📗 Installation de Node.js 18...${NC}"
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# 4. Installation de yt-dlp
echo -e "\n${YELLOW}📺 Installation de yt-dlp...${NC}"
pipx ensurepath
export PATH="$PATH:/root/.local/bin"
pipx install yt-dlp || pipx upgrade yt-dlp

# 5. Cloner le repository
echo -e "\n${YELLOW}📥 Téléchargement depuis GitHub...${NC}"
cd /opt
if [ -d "youtu-selfhost" ]; then
    echo "Mise à jour du repository existant..."
    cd youtu-selfhost
    git pull
else
    git clone https://github.com/Reaper-Official/youtu-selfhost.git
    cd youtu-selfhost
fi

# 6. Configuration Backend
echo -e "\n${YELLOW}⚙️ Configuration du backend...${NC}"
cd /opt/youtu-selfhost/backend
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate

# Configuration .env
if [ ! -f .env ]; then
    cp .env.example .env
    
    # Demander le chemin des vidéos
    echo -e "\n${YELLOW}📁 Configuration du dossier vidéos${NC}"
    read -p "Chemin des vidéos (défaut: /opt/youtube-videos): " VIDEO_PATH
    VIDEO_PATH=${VIDEO_PATH:-/opt/youtube-videos}
    
    mkdir -p "$VIDEO_PATH"
    sed -i "s|MEDIA_PATH=.*|MEDIA_PATH=$VIDEO_PATH|g" .env
fi

# 7. Configuration Frontend
echo -e "\n${YELLOW}🎨 Configuration du frontend...${NC}"
cd /opt/youtu-selfhost/frontend
npm install

# 8. Création des scripts de lancement
echo -e "\n${YELLOW}🚀 Création des scripts de lancement...${NC}"

# Obtenir l'IP
SERVER_IP=$(hostname -I | awk '{print $1}')

cat > /opt/youtu-selfhost/start.sh << EOF
#!/bin/bash
echo "🚀 Démarrage de YouTube Library..."

# Arrêter les instances existantes
screen -S youtube-backend -X quit 2>/dev/null
screen -S youtube-frontend -X quit 2>/dev/null

# Démarrer le backend
screen -dmS youtube-backend bash -c 'cd /opt/youtu-selfhost/backend && source venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload'

# Attendre que le backend démarre
sleep 5

# Démarrer le frontend
screen -dmS youtube-frontend bash -c 'cd /opt/youtu-selfhost/frontend && HOST=0.0.0.0 npm start'

echo "✅ YouTube Library est démarré!"
echo ""
echo "📺 Interface: http://$SERVER_IP:3000"
echo "⚙️  API: http://$SERVER_IP:8000"
echo "📚 Docs: http://$SERVER_IP:8000/docs"
echo ""
echo "Logs: screen -r youtube-backend / screen -r youtube-frontend"
EOF

cat > /opt/youtu-selfhost/stop.sh << 'EOF'
#!/bin/bash
echo "🛑 Arrêt de YouTube Library..."
screen -S youtube-backend -X quit
screen -S youtube-frontend -X quit
echo "✅ Arrêté"
EOF

chmod +x /opt/youtu-selfhost/*.sh

# 9. Créer les raccourcis
ln -sf /opt/youtu-selfhost/start.sh /usr/local/bin/youtube-start
ln -sf /opt/youtu-selfhost/stop.sh /usr/local/bin/youtube-stop

# 10. Service systemd
cat > /etc/systemd/system/youtube-library.service << EOF
[Unit]
Description=YouTube Library
After=network.target

[Service]
Type=forking
ExecStart=/opt/youtu-selfhost/start.sh
ExecStop=/opt/youtu-selfhost/stop.sh
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable youtube-library

# 11. Démarrer l'application
echo -e "\n${YELLOW}🚀 Démarrage de l'application...${NC}"
/opt/youtu-selfhost/start.sh

# 12. Affichage final
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✅ Installation terminée avec succès!      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}🌐 ACCÈS:${NC}"
echo -e "   Interface: ${GREEN}http://$SERVER_IP:3000${NC}"
echo -e "   API: ${GREEN}http://$SERVER_IP:8000${NC}"
echo -e "   Docs: ${GREEN}http://$SERVER_IP:8000/docs${NC}"
echo ""
echo -e "${YELLOW}📁 Vidéos: ${GREEN}$VIDEO_PATH${NC}"
echo ""
echo -e "${YELLOW}🔧 COMMANDES:${NC}"
echo -e "   Démarrer: ${GREEN}youtube-start${NC}"
echo -e "   Arrêter: ${GREEN}youtube-stop${NC}"
echo -e "   Logs backend: ${GREEN}screen -r youtube-backend${NC}"
echo -e "   Logs frontend: ${GREEN}screen -r youtube-frontend${NC}"
echo ""
echo -e "${BLUE}L'application démarre automatiquement au boot!${NC}"
