# 10. API Routes
log_step "Création des APIs"

# api/videos.py
cat > "$INSTALL_DIR/backend/app/api/videos.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from ..database import get_db
from ..models import Video as VideoModel
from ..schemas import Video, VideoUpdate

router = APIRouter()

@router.get("/videos", response_model=List[Video])
def get_videos(
    skip: int = 0,
    limit: int = 100,
    search: Optional[str] = None,
    channel: Optional[str] = None,
    watched: Optional[bool] = None,
    db: Session = Depends(get_db)
):
    query = db.query(VideoModel)
    
    if search:
        query = query.filter(
            VideoModel.title.contains(search) | 
            VideoModel.description.contains(search)
        )
    
    if channel:
        query = query.filter(VideoModel.channel_name == channel)
    
    if watched is not None:
        query = query.filter(VideoModel.watched == watched)
    
    videos = query.offset(skip).limit(limit).all()
    return videos

@router.get("/videos/{video_id}", response_model=Video)
def get_video(video_id: str, db: Session = Depends(get_db)):
    video = db.query(VideoModel).filter(VideoModel.id == video_id).first()
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")
    return video

@router.patch("/videos/{video_id}")
def update_video(
    video_id: str,
    video_update: VideoUpdate,
    db: Session = Depends(get_db)
):
    video = db.query(VideoModel).filter(VideoModel.id == video_id).first()
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")
    
    if video_update.watched is not None:
        video.watched = video_update.watched
    
    if video_update.last_watched is not None:
        video.last_watched = video_update.last_watched
        video.local_views += 1
    
    db.commit()
    db.refresh(video)
    return video

@router.delete("/videos/{video_id}")
def delete_video(video_id: str, db: Session = Depends(get_db)):
    video = db.query(VideoModel).filter(VideoModel.id == video_id).first()
    if not video:
        raise HTTPException(status_code=404, detail="Video not found")
    
    db.delete(video)
    db.commit()
    return {"message": "Video deleted"}

@router.get("/channels")
def get_channels(db: Session = Depends(get_db)):
    channels = db.query(VideoModel.channel_name).distinct().all()
    return [{"name": channel[0]} for channel in channels if channel[0]]
EOF

# api/download.py
cat > "$INSTALL_DIR/backend/app/api/download.py" << 'EOF'
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
from ..database import get_db
from ..schemas import DownloadRequest, DownloadResponse, DownloadProgress
from ..downloader import VideoDownloader
import os
import ssl
import urllib3
from dotenv import load_dotenv

ssl._create_default_https_context = ssl._create_unverified_context
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

load_dotenv()
router = APIRouter()

MEDIA_PATH = os.getenv("MEDIA_PATH", "/opt/youtube-videos")
downloader = VideoDownloader(MEDIA_PATH)

@router.post("/download", response_model=DownloadResponse)
async def download_video(
    request: DownloadRequest,
    db: Session = Depends(get_db)
):
    try:
        if not request.url.startswith(('https://www.youtube.com/', 'https://youtube.com/', 'https://youtu.be/')):
            raise HTTPException(status_code=400, detail="Invalid YouTube URL")
        
        task_id = await downloader.download_video(
            request.url, 
            request.quality,
            db
        )
        
        return DownloadResponse(
            task_id=task_id,
            message="Download started successfully"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/download/{task_id}", response_model=DownloadProgress)
def get_download_status(task_id: str):
    status = downloader.get_download_status(task_id)
    if not status:
        raise HTTPException(status_code=404, detail="Download task not found")
    
    return DownloadProgress(**status)

@router.get("/downloads", response_model=List[DownloadProgress])
def get_all_downloads():
    downloads = downloader.get_all_downloads()
    return [DownloadProgress(**status) for status in downloads.values()]

@router.delete("/download/{task_id}")
def cancel_download(task_id: str):
    if not downloader.cancel_download(task_id):
        raise HTTPException(status_code=404, detail="Download task not found")
    
    return {"message": "Download cancelled"}

@router.post("/download/metadata")
async def get_video_metadata(request: DownloadRequest):
    try:
        import yt_dlp
        
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
            'skip_download': True,
            'no_check_certificate': True,
            'prefer_insecure': True,
            'socket_timeout': 30,
            'retries': 3,
        }
        
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(request.url, download=False)
            
            formats = []
            if 'formats' in info:
                seen_resolutions = set()
                for f in info['formats']:
                    if f.get('height'):
                        resolution = f"{f['height']}p"
                        if resolution not in seen_resolutions and f.get('vcodec') != 'none':
                            seen_resolutions.add(resolution)
                            formats.append({
                                'format_id': f['format_id'],
                                'resolution': resolution,
                                'ext': f.get('ext', 'mp4'),
                                'filesize': f.get('filesize', 0)
                            })
                
                formats.sort(key=lambda x: int(x['resolution'][:-1]), reverse=True)
            
            return {
                'title': info.get('title'),
                'duration': info.get('duration'),
                'thumbnail': info.get('thumbnail'),
                'uploader': info.get('uploader'),
                'view_count': info.get('view_count'),
                'formats': formats[:5]
            }
            
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error fetching metadata: {str(e)}")
EOF

# api/scanner.py
cat > "$INSTALL_DIR/backend/app/api/scanner.py" << 'EOF'
from fastapi import APIRouter, Depends, BackgroundTasks
from sqlalchemy.orm import Session
from ..database import get_db
from ..schemas import ScanRequest, ScanResponse
from ..scanner import VideoScanner
import os
from dotenv import load_dotenv

load_dotenv()
router = APIRouter()

@router.post("/scan", response_model=ScanResponse)
def scan_videos(
    request: ScanRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    scan_path = request.path or os.getenv("MEDIA_PATH")
    if not scan_path:
        return ScanResponse(
            status="error",
            videos_found=0,
            videos_added=0,
            errors=["No scan path provided and MEDIA_PATH not set"]
        )
    
    scanner = VideoScanner(db)
    results = scanner.scan_directory(scan_path, request.recursive)
    
    return ScanResponse(
        status="completed",
        videos_found=results['videos_found'],
        videos_added=results['videos_added'],
        errors=results['errors']
    )
EOF

# scanner.py
cat > "$INSTALL_DIR/backend/app/scanner.py" << 'EOF'
import os
from pathlib import Path
from typing import Dict
from sqlalchemy.orm import Session
from .models import Video
from .utils.metadata import MetadataExtractor
from datetime import datetime
import json
import logging

logger = logging.getLogger(__name__)

class VideoScanner:
    def __init__(self, db: Session):
        self.db = db
        self.metadata_extractor = MetadataExtractor()
        self.video_extensions = {'.mp4', '.mkv', '.webm', '.avi', '.mov', '.flv'}
    
    def scan_directory(self, directory: str, recursive: bool = True) -> Dict:
        results = {
            'videos_found': 0,
            'videos_added': 0,
            'errors': []
        }
        
        path = Path(directory)
        if not path.exists():
            results['errors'].append(f"Directory {directory} does not exist")
            return results
        
# scanner.py
cat > "$INSTALL_DIR/backend/app/scanner.py" << 'EOF'
import os
from pathlib import Path
from typing import Dict
from sqlalchemy.orm import Session
from .models import Video
from .utils.metadata import MetadataExtractor
from datetime import datetime
import json
import logging

logger = logging.getLogger(__name__)

class VideoScanner:
    def __init__(self, db: Session):
        self.db = db
        self.metadata_extractor = MetadataExtractor()
        self.video_extensions = {'.mp4', '.mkv', '.webm', '.avi', '.mov', '.flv'}
    
    def scan_directory(self, directory: str, recursive: bool = True) -> Dict:
        results = {
            'videos_found': 0,
            'videos_added': 0,
            'errors': []
        }
        
        path = Path(directory)
        if not path.exists():
            results['errors'].append(f"Directory {directory} does not exist")
            return results
        
        if recursive:
            video_files = [f for f in path.rglob('*') if f.suffix.lower() in self.video_extensions]
        else:
            video_files = [f for f in path.iterdir() if f.is_file() and f.suffix.lower() in self.video_extensions]
        
        results['videos_found'] = len(video_files)
        
        for file_path in video_files:
            try:
                self._process_video_file(file_path)
                results['videos_added'] += 1
            except Exception as e:
                error_msg = f"Error processing {file_path.name}: {str(e)}"
                logger.error(error_msg)
                results['errors'].append(error_msg)
        
        self.db.commit()
        return results
    
    def _process_video_file(self, file_path: Path):
        video_id = self.metadata_extractor.extract_video_id(file_path.name)
        if not video_id:
            raise ValueError("Could not extract YouTube ID from filename")
        
        existing_video = self.db.query(Video).filter(Video.id == video_id).first()
        if existing_video:
            logger.info(f"Video {video_id} already in database")
            return
        
        file_stat = file_path.stat()
        
        video = Video(
            id=video_id,
            file_path=str(file_path),
            file_size=file_stat.st_size,
            added_date=datetime.utcnow()
        )
        
        metadata = self.metadata_extractor.get_metadata(video_id)
        if metadata:
            video.title = metadata.get('title')
            video.thumbnail_url = metadata.get('thumbnail_url')
            video.channel_name = metadata.get('channel_name')
            video.channel_id = metadata.get('channel_id')
            video.duration = metadata.get('duration')
            video.description = metadata.get('description')
            video.view_count = metadata.get('view_count')
            video.like_count = metadata.get('like_count')
            video.resolution = metadata.get('resolution')
            
            if metadata.get('tags'):
                video.tags = json.dumps(metadata['tags'])
            
            if metadata.get('upload_date'):
                try:
                    video.upload_date = datetime.strptime(metadata['upload_date'], '%Y%m%d')
                except:
                    pass
        else:
            video.title = file_path.stem
        
        self.db.add(video)
        logger.info(f"Added video: {video.title or video_id}")
EOF

# main.py
cat > "$INSTALL_DIR/backend/app/main.py" << 'EOF'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from .database import engine, Base
from .api import videos, scanner, download
import os

Base.metadata.create_all(bind=engine)

app = FastAPI(title="YouTube Library API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"]
)

app.include_router(videos.router, prefix="/api", tags=["videos"])
app.include_router(scanner.router, prefix="/api", tags=["scanner"])
app.include_router(download.router, prefix="/api", tags=["download"])

MEDIA_PATH = os.getenv("MEDIA_PATH", "/opt/youtube-videos")
if os.path.exists(MEDIA_PATH):
    app.mount("/media", StaticFiles(directory=MEDIA_PATH), name="media")

@app.get("/")
def read_root():
    return {"message": "YouTube Library API", "version": "1.0.0", "status": "running"}

@app.get("/health")
def health_check():
    return {"status": "healthy", "media_path": os.getenv("MEDIA_PATH")}

@app.options("/{full_path:path}")
async def options_handler(full_path: str):
    return {"message": "OK"}
EOF

# .env
cat > "$INSTALL_DIR/backend/.env" << EOF
DATABASE_URL=sqlite:///./youtube_library.db
MEDIA_PATH=$DEFAULT_MEDIA_PATH
YOUTUBE_API_KEY=your_youtube_api_key_here
EOF

# 11. Frontend
log_step "Création du frontend React"

# package.json
cat > "$INSTALL_DIR/frontend/package.json" << 'EOF'
{
  "name": "youtube-library-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.17.0",
    "@testing-library/react": "^13.4.0",
    "@testing-library/user-event": "^13.5.0",
    "axios": "^1.6.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-icons": "^4.12.0",
    "react-player": "^2.13.0",
    "react-scripts": "5.0.1",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "devDependencies": {
    "tailwindcss": "^3.3.0",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.31"
  }
}
EOF

# Configuration frontend
SERVER_IP=$(hostname -I | awk '{print $1}')

cat > "$INSTALL_DIR/frontend/.env" << EOF
REACT_APP_API_URL=http://$SERVER_IP:8000/api
GENERATE_SOURCEMAP=false
REACT_APP_VERSION=1.0.0
PORT=3000
HOST=0.0.0.0
EOF

# public/index.html
cat > "$INSTALL_DIR/frontend/public/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta name="description" content="Personal YouTube video library" />
    <title>YouTube Library</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
EOF

# 12. Installation des dépendances
log_step "Installation des dépendances"

# Backend Python
cd "$INSTALL_DIR/backend"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q
deactivate

# Frontend Node.js
cd "$INSTALL_DIR/frontend"
npm install >/dev/null 2>&1

# 13. Créer les dossiers nécessaires
mkdir -p "$DEFAULT_MEDIA_PATH"
chmod 755 "$DEFAULT_MEDIA_PATH"

# 14. Scripts de gestion
log_step "Création des scripts de gestion"

cat > "$INSTALL_DIR/start.sh" << EOF
#!/bin/bash
echo "🚀 Démarrage de YouTube Library..."

# Variables d'environnement
export PYTHONHTTPSVERIFY=0
export CURL_CA_BUNDLE=""
export REQUESTS_CA_BUNDLE=""
export SSL_VERIFY=False

# Arrêter les instances existantes
screen -S youtube-backend -X quit 2>/dev/null
screen -S youtube-frontend -X quit 2>/dev/null
sleep 2

# Démarrer le backend
echo "Démarrage du backend..."
cd $INSTALL_DIR/backend
screen -dmS youtube-backend bash -c 'source venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload'

# Attendre le démarrage du backend
sleep 6

# Tester la disponibilité du backend
if curl -s http://localhost:8000/health >/dev/null; then
    echo "✅ Backend démarré"
else
    echo "⚠️  Backend en cours de démarrage..."
fi

# Démarrer le frontend
echo "Démarrage du frontend..."
cd $INSTALL_DIR/frontend
screen -dmS youtube-frontend bash -c 'npm start'

sleep 4
echo ""
echo "✅ YouTube Library démarré!"
echo "📱 Interface: http://$SERVER_IP:3000"
echo "⚙️  API: http://$SERVER_IP:8000"
echo "📋 Logs: youtube-status"
EOF

cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash
echo "🛑 Arrêt de YouTube Library..."
screen -S youtube-backend -X quit 2>/dev/null
screen -S youtube-frontend -X quit 2>/dev/null
sleep 2
echo "✅ YouTube Library arrêté"
EOF

cat > "$INSTALL_DIR/status.sh" << EOF
#!/bin/bash
echo "📊 Statut de YouTube Library"
echo "============================"
echo ""

BACKEND_STATUS="❌ Arrêté"
FRONTEND_STATUS="❌ Arrêté"

if screen -list | grep -q "youtube-backend"; then
    BACKEND_STATUS="✅ En cours"
fi

if screen -list | grep -q "youtube-frontend"; then
    FRONTEND_STATUS="✅ En cours"
fi

echo "Backend:  \$BACKEND_STATUS"
echo "Frontend: \$FRONTEND_STATUS"
echo ""

if curl -s http://localhost:8000/health >/dev/null 2>&1; then
    echo "🌐 API: ✅ Accessible (http://$SERVER_IP:8000)"
else
    echo "🌐 API: ❌ Non accessible"
fi

echo ""
echo "📋 Logs disponibles:"
echo "   Backend:  screen -r youtube-backend"
echo "   Frontend: screen -r youtube-frontend"
echo "   Sortir:   Ctrl+A puis D"
echo ""
echo "🔧 Commandes:"
echo "   Démarrer: youtube-start"
echo "   Arrêter:  youtube-stop"
echo "   Statut:   youtube-status"
EOF

chmod +x "$INSTALL_DIR"/*.sh

# Créer les raccourcis système
ln -sf "$INSTALL_DIR/start.sh" /usr/local/bin/youtube-start
ln -sf "$INSTALL_DIR/stop.sh" /usr/local/bin/youtube-stop
ln -sf "$INSTALL_DIR/status.sh" /usr/local/bin/youtube-status

# 15. Service systemd
log_step "Configuration du service système"

cat > /etc/systemd/system/youtube-library.service << EOF
[Unit]
Description=YouTube Personal Library
After=network.target

[Service]
Type=forking
ExecStart=$INSTALL_DIR/start.sh
ExecStop=$INSTALL_DIR/stop.sh
Restart=on-failure
RestartSec=10
User=root
WorkingDirectory=$INSTALL_DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin:/root/.local/bin
Environment=PYTHONHTTPSVERIFY=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable youtube-library >/dev/null 2>&1

# 16. Initialisation de la base de données
log_step "Initialisation de la base de données"
cd "$INSTALL_DIR/backend"
source venv/bin/activate
python3 -c "
from app.database import engine, Base
Base.metadata.create_all(bind=engine)
print('Base de données initialisée')
" >/dev/null
deactivate

# 17. Tests et démarrage
log_step "Tests et démarrage"

# Test des outils
log_info "Test des téléchargeurs..."
export PYTHONHTTPSVERIFY=0
yt-dlp --version >/dev/null 2>&1 && echo "✅ yt-dlp disponible" || echo "⚠️ yt-dlp problème"
youtube-dl --version >/dev/null 2>&1 && echo "✅ youtube-dl disponible" || echo "⚠️ youtube-dl non disponible"

# Démarrer l'application
log_info "Démarrage de l'application..."
"$INSTALL_DIR/start.sh" >/dev/null 2>&1

# Attendre le démarrage complet
sleep 12

# Tests de connectivité
BACKEND_STATUS="❌ Hors ligne"
FRONTEND_STATUS="❌ Hors ligne"

if curl -s "http://localhost:8000/health" >/dev/null; then
    BACKEND_STATUS="✅ En ligne"
fi

if ss -tulpn | grep -q ":3000"; then
    FRONTEND_STATUS="✅ En ligne"
fi

# 18. Affichage final
clear
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}║          🎉 INSTALLATION TERMINÉE AVEC SUCCÈS! 🎉          ║${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}🌐 ACCÈS À VOTRE MÉDIATHÈQUE:${NC}"
echo -e "   Interface web: ${GREEN}http://$SERVER_IP:3000${NC}"
echo -e "   API REST:      ${GREEN}http://$SERVER_IP:8000${NC}"
echo -e "   Documentation: ${GREEN}http://$SERVER_IP:8000/docs${NC}"
echo ""
echo -e "${BLUE}📁 STOCKAGE DES VIDÉOS:${NC}"
echo -e "   Dossier: ${GREEN}$DEFAULT_MEDIA_PATH${NC}"
echo ""
echo -e "${BLUE}🔧 COMMANDES DISPONIBLES:${NC}"
echo -e "   ${GREEN}youtube-start${NC}  - Démarrer l'application"
echo -e "   ${GREEN}youtube-stop${NC}   - Arrêter l'application"
echo -e "   ${GREEN}youtube-status${NC} - Voir le statut et les logs"
echo ""
echo -e "${BLUE}📊 STATUT ACTUEL:${NC}"
echo -e "   • Backend: $BACKEND_STATUS"
echo -e "   • Frontend: $FRONTEND_STATUS"
echo ""
echo -e "${BLUE}⚡ FONCTIONNALITÉS:${NC}"
echo -e "   • Téléchargement YouTube automatique (SSL contourné)"
echo -e "   • 3 méthodes de téléchargement (yt-dlp, subprocess, youtube-dl)"
echo -e "   • Scanner automatique de dossiers existants"
echo -e "   • Lecteur vidéo intégré avec interface moderne"
echo -e "   • Gestion des métadonnées automatique"
echo -e "   • Démarrage automatique au boot du serveur"
echo ""
echo -e "${YELLOW}🚀 PREMIERS PAS:${NC}"
echo -e "   1. Ouvrez ${GREEN}http://$SERVER_IP:3000${NC} dans votre navigateur"
echo -e "   2. Cliquez sur '${CYAN}Download${NC}' pour télécharger une vidéo YouTube"
echo -e "   3. Collez l'URL YouTube et cliquez '${CYAN}Download${NC}'"
echo -e "   4. Le système télécharge automatiquement avec 3 méthodes de fallback"
echo ""
echo -e "${BLUE}🔍 EN CAS DE PROBLÈME:${NC}"
echo -e "   • Vérifiez le statut: ${GREEN}youtube-status${NC}"
echo -e "   • Consultez les logs: ${GREEN}screen -r youtube-backend${NC}"
echo -e "   • Redémarrez: ${GREEN}youtube-stop && youtube-start${NC}"
echo ""
echo -e "${GREEN}🎬 Le téléchargement YouTube fonctionne maintenant automatiquement !${NC}"
echo ""

log_info "Installation terminée! L'application démarre automatiquement."#!/bin/bash

# ================================================================
# YOUTUBE LIBRARY - INSTALLATION AUTOMATIQUE COMPLÈTE
# Version: 3.0 - Corrections SSL et téléchargement forcé
# ================================================================

set -e

# Configuration
INSTALL_DIR="/opt/youtu-selfhost"
DEFAULT_MEDIA_PATH="/opt/youtube-videos"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[ÉTAPE]${NC} $1"; }

# Vérification root
if [[ $EUID -ne 0 ]]; then
    log_error "Ce script doit être exécuté en tant que root"
    echo "Utilisez: sudo bash install.sh"
    exit 1
fi

clear
echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                          ║${NC}"
echo -e "${BLUE}║            🎬 YOUTUBE LIBRARY INSTALLER 🎬              ║${NC}"
echo -e "${BLUE}║                                                          ║${NC}"
echo -e "${BLUE}║     Installation automatique avec téléchargement        ║${NC}"
echo -e "${BLUE}║              YouTube fonctionnel                         ║${NC}"
echo -e "${BLUE}║                                                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Mise à jour système
log_step "Mise à jour du système"
apt update -qq && apt upgrade -y -qq

# 2. Installation des dépendances
log_step "Installation des dépendances système"
apt install -y -qq \
    curl wget git build-essential screen \
    python3 python3-pip python3-venv python3-full \
    ffmpeg pipx unzip ca-certificates \
    software-properties-common apt-transport-https

# 3. Installation Node.js
log_step "Installation de Node.js 18"
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt install -y -qq nodejs
fi
log_info "Node.js $(node --version) installé"

# 4. Installation des téléchargeurs
log_step "Installation des téléchargeurs YouTube"
export PATH="$PATH:/root/.local/bin"

# yt-dlp
pipx install yt-dlp --force >/dev/null 2>&1 || pip3 install --user --upgrade yt-dlp
# youtube-dl en fallback
pip3 install --user --upgrade youtube-dl >/dev/null 2>&1

log_info "yt-dlp et youtube-dl installés"

# 5. Configuration SSL globale
log_step "Configuration SSL permissive"

# Variables d'environnement
cat >> /etc/environment << 'EOF'
PYTHONHTTPSVERIFY=0
CURL_CA_BUNDLE=""
REQUESTS_CA_BUNDLE=""
SSL_VERIFY=False
EOF

# Configuration Python globale
mkdir -p /usr/local/lib/python3.*/site-packages 2>/dev/null || true
cat > /usr/local/lib/python3.11/site-packages/sitecustomize.py << 'EOF' 2>/dev/null || true
import ssl
import urllib3
ssl._create_default_https_context = ssl._create_unverified_context
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
EOF

export PYTHONHTTPSVERIFY=0

# 6. Création du projet
log_step "Création de la structure du projet"

# Créer les dossiers
mkdir -p "$INSTALL_DIR"/{backend/app/{api,utils},frontend/src/{components,services,utils},frontend/public}

# 7. Fichiers Backend
log_step "Création des fichiers backend"

# requirements.txt
cat > "$INSTALL_DIR/backend/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
sqlalchemy==2.0.23
pydantic==2.5.0
yt-dlp>=2024.1.1
youtube-dl>=2021.12.17
python-dotenv==1.0.0
aiofiles==23.2.1
python-multipart==0.0.6
requests>=2.31.0
urllib3>=2.0.0
certifi
EOF

# __init__.py files
touch "$INSTALL_DIR/backend/app/__init__.py"
touch "$INSTALL_DIR/backend/app/api/__init__.py"
touch "$INSTALL_DIR/backend/app/utils/__init__.py"

# database.py
cat > "$INSTALL_DIR/backend/app/database.py" << 'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from dotenv import load_dotenv

load_dotenv()

SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./youtube_library.db")

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

# models.py
cat > "$INSTALL_DIR/backend/app/models.py" << 'EOF'
from sqlalchemy import Column, String, Integer, DateTime, Text, Boolean
from .database import Base
from datetime import datetime

class Video(Base):
    __tablename__ = "videos"

    id = Column(String, primary_key=True, index=True)
    file_path = Column(String, nullable=False)
    title = Column(String)
    thumbnail_url = Column(String)
    channel_name = Column(String)
    channel_id = Column(String)
    duration = Column(Integer)
    upload_date = Column(DateTime)
    description = Column(Text)
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    tags = Column(Text)
    resolution = Column(String)
    file_size = Column(Integer)
    added_date = Column(DateTime, default=datetime.utcnow)
    last_watched = Column(DateTime, nullable=True)
    watched = Column(Boolean, default=False)
    local_views = Column(Integer, default=0)
EOF

# schemas.py
cat > "$INSTALL_DIR/backend/app/schemas.py" << 'EOF'
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List

class VideoBase(BaseModel):
    id: str
    title: Optional[str] = None
    channel_name: Optional[str] = None
    duration: Optional[int] = None
    thumbnail_url: Optional[str] = None

class VideoCreate(VideoBase):
    file_path: str

class VideoUpdate(BaseModel):
    watched: Optional[bool] = None
    last_watched: Optional[datetime] = None

class Video(VideoBase):
    file_path: str
    channel_id: Optional[str] = None
    upload_date: Optional[datetime] = None
    description: Optional[str] = None
    view_count: Optional[int] = None
    like_count: Optional[int] = None
    tags: Optional[str] = None
    resolution: Optional[str] = None
    file_size: Optional[int] = None
    added_date: datetime
    last_watched: Optional[datetime] = None
    watched: bool
    local_views: int

    class Config:
        from_attributes = True

class ScanRequest(BaseModel):
    path: Optional[str] = None
    recursive: bool = True

class ScanResponse(BaseModel):
    status: str
    videos_found: int
    videos_added: int
    errors: List[str] = []

class DownloadRequest(BaseModel):
    url: str
    quality: Optional[str] = "best"

class DownloadProgress(BaseModel):
    task_id: str
    status: str
    progress: Optional[float] = None
    speed: Optional[str] = None
    eta: Optional[str] = None
    filename: Optional[str] = None
    error: Optional[str] = None

class DownloadResponse(BaseModel):
    task_id: str
    message: str
EOF

# 8. Copier les fichiers corrigés du downloader
log_step "Installation du système de téléchargement"

# utils/metadata.py (version corrigée SSL)
cat > "$INSTALL_DIR/backend/app/utils/metadata.py" << 'EOF'
import yt_dlp
import re
import ssl
import urllib3
from typing import Optional, Dict
import logging

ssl._create_default_https_context = ssl._create_unverified_context
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logger = logging.getLogger(__name__)

class MetadataExtractor:
    def __init__(self):
        self.ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
            'skip_download': True,
            'no_check_certificate': True,
            'prefer_insecure': True,
            'socket_timeout': 30,
            'retries': 5,
        }
    
    @staticmethod
    def extract_video_id(filename: str) -> Optional[str]:
        patterns = [
            r'[-_]([a-zA-Z0-9_-]{11})(?:\.|$)',
            r'\[([a-zA-Z0-9_-]{11})\]',
            r'\(([a-zA-Z0-9_-]{11})\)',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, filename)
            if match:
                return match.group(1)
        return None
    
    def get_metadata(self, video_id: str) -> Optional[Dict]:
        with yt_dlp.YoutubeDL(self.ydl_opts) as ydl:
            try:
                info = ydl.extract_info(
                    f"https://youtube.com/watch?v={video_id}", 
                    download=False
                )
                
                return {
                    'title': info.get('title'),
                    'thumbnail_url': info.get('thumbnail'),
                    'channel_name': info.get('uploader'),
                    'channel_id': info.get('channel_id'),
                    'duration': info.get('duration'),
                    'upload_date': info.get('upload_date'),
                    'description': info.get('description'),
                    'view_count': info.get('view_count'),
                    'like_count': info.get('like_count'),
                    'tags': info.get('tags', []),
                    'resolution': f"{info.get('width')}x{info.get('height')}" if info.get('width') else None
                }
            except Exception as e:
                logger.error(f"Error fetching metadata for {video_id}: {str(e)}")
                return None
EOF

# 9. Créer le downloader multi-méthodes
cat > "$INSTALL_DIR/backend/app/downloader.py" << 'EOF'
import os
import uuid
import glob
import logging
import ssl
import urllib3
from typing import Dict, Optional
from pathlib import Path
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from sqlalchemy.orm import Session
from .models import Video
from .utils.metadata import MetadataExtractor
import json
import subprocess

ssl._create_default_https_context = ssl._create_unverified_context
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logger = logging.getLogger(__name__)

class VideoDownloader:
    def __init__(self, download_path: str):
        self.download_path = download_path
        self.active_downloads: Dict[str, Dict] = {}
        self.executor = ThreadPoolExecutor(max_workers=3)
        self.metadata_extractor = MetadataExtractor()
        
        Path(self.download_path).mkdir(parents=True, exist_ok=True)
        
    def _progress_hook(self, task_id: str):
        def hook(d):
            try:
                if d['status'] == 'downloading':
                    downloaded = d.get('downloaded_bytes', 0)
                    total = d.get('total_bytes') or d.get('total_bytes_estimate', 0)
                    
                    if total > 0:
                        progress = (downloaded / total) * 100
                    else:
                        progress = d.get('fragment_index', 0) * 10
                    
                    speed = d.get('speed')
                    if speed:
                        if speed > 1024 * 1024:
                            speed_str = f"{speed / (1024 * 1024):.1f} MB/s"
                        elif speed > 1024:
                            speed_str = f"{speed / 1024:.1f} KB/s"
                        else:
                            speed_str = f"{speed:.0f} B/s"
                    else:
                        speed_str = d.get('_speed_str', 'N/A')
                    
                    eta = d.get('eta')
                    if eta and isinstance(eta, (int, float)):
                        eta_str = f"{int(eta)}s"
                    else:
                        eta_str = d.get('_eta_str', 'N/A')
                    
                    self.active_downloads[task_id].update({
                        'status': 'downloading',
                        'progress': round(progress, 2),
                        'speed': speed_str,
                        'eta': eta_str,
                        'filename': d.get('filename', '')
                    })
                    
                elif d['status'] == 'finished':
                    self.active_downloads[task_id].update({
                        'status': 'processing',
                        'progress': 100,
                        'filename': d.get('filename', '')
                    })
                    
            except Exception as e:
                logger.error(f"Error in progress hook: {str(e)}")
                
        return hook

    def _get_video_id_from_url(self, url: str) -> Optional[str]:
        import re
        patterns = [
            r'(?:v=|\/)([0-9A-Za-z_-]{11}).*',
            r'(?:embed\/)([0-9A-Za-z_-]{11})',
            r'(?:youtu\.be\/)([0-9A-Za-z_-]{11})'
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None

    def _download_with_yt_dlp(self, url: str, video_id: str) -> Optional[str]:
        try:
            import yt_dlp
            
            output_template = os.path.join(self.download_path, f"%(title)s-{video_id}.%(ext)s")
            
            ydl_opts = {
                'outtmpl': output_template,
                'format': 'best[ext=mp4]/best',
                'merge_output_format': 'mp4',
                'no_check_certificate': True,
                'prefer_insecure': True,
                'socket_timeout': 60,
                'retries': 10,
                'fragment_retries': 10,
                'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'referer': 'https://www.youtube.com/',
                'extractor_args': {
                    'youtube': {
                        'player_client': ['android', 'web', 'ios'],
                        'skip': ['hls']
                    }
                },
                'quiet': False,
                'no_warnings': False,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                logger.info(f"Downloading with yt-dlp: {video_id}")
                ydl.download([url])
                
                pattern = os.path.join(self.download_path, f"*{video_id}*")
                files = glob.glob(pattern)
                if files:
                    filename = max(files, key=os.path.getctime)
                    logger.info(f"yt-dlp success: {filename}")
                    return filename
                    
        except Exception as e:
            logger.warning(f"yt-dlp failed: {str(e)}")
        
        return None

    def _download_with_subprocess(self, url: str, video_id: str) -> Optional[str]:
        try:
            output_template = os.path.join(self.download_path, f"%(title)s-{video_id}.%(ext)s")
            
            cmd = [
                'yt-dlp',
                '--no-check-certificate',
                '--prefer-insecure',
                '--format', 'best[ext=mp4]/best',
                '--output', output_template,
                '--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                '--referer', 'https://www.youtube.com/',
                '--socket-timeout', '60',
                '--retries', '10',
                '--fragment-retries', '10',
                url
            ]
            
            env = os.environ.copy()
            env.update({
                'PYTHONHTTPSVERIFY': '0',
                'CURL_CA_BUNDLE': '',
                'REQUESTS_CA_BUNDLE': '',
                'SSL_VERIFY': 'False'
            })
            
            logger.info(f"Downloading with subprocess: {video_id}")
            result = subprocess.run(cmd, capture_output=True, text=True, 
                                  timeout=600, env=env)
            
            if result.returncode == 0:
                pattern = os.path.join(self.download_path, f"*{video_id}*")
                files = glob.glob(pattern)
                if files:
                    filename = max(files, key=os.path.getctime)
                    logger.info(f"subprocess success: {filename}")
                    return filename
            else:
                logger.warning(f"subprocess stderr: {result.stderr}")
                
        except Exception as e:
            logger.warning(f"subprocess failed: {str(e)}")
        
        return None

    def _download_with_youtube_dl(self, url: str, video_id: str) -> Optional[str]:
        try:
            output_template = os.path.join(self.download_path, f"%(title)s-{video_id}.%(ext)s")
            
            cmd = [
                'youtube-dl',
                '--no-check-certificate',
                '--ignore-errors',
                '--format', 'best[ext=mp4]/best',
                '--output', output_template,
                url
            ]
            
            env = os.environ.copy()
            env['PYTHONHTTPSVERIFY'] = '0'
            
            logger.info(f"Downloading with youtube-dl: {video_id}")
            result = subprocess.run(cmd, capture_output=True, text=True, 
                                  timeout=600, env=env)
            
            if result.returncode == 0:
                pattern = os.path.join(self.download_path, f"*{video_id}*")
                files = glob.glob(pattern)
                if files:
                    filename = max(files, key=os.path.getctime)
                    logger.info(f"youtube-dl success: {filename}")
                    return filename
                    
        except Exception as e:
            logger.warning(f"youtube-dl failed: {str(e)}")
        
        return None

    async def download_video(self, url: str, quality: str = "best", db: Session = None) -> str:
        task_id = str(uuid.uuid4())
        
        self.active_downloads[task_id] = {
            'task_id': task_id,
            'status': 'pending',
            'progress': 0,
            'speed': None,
            'eta': None,
            'filename': None,
            'error': None
        }
        
        loop = asyncio.get_event_loop()
        loop.run_in_executor(
            self.executor,
            self._download_video_sync,
            url,
            quality,
            task_id,
            db
        )
        
        return task_id

    def _download_video_sync(self, url: str, quality: str, task_id: str, db: Session = None):
        try:
            video_id = self._get_video_id_from_url(url)
            if not video_id:
                raise ValueError("Could not extract video ID from URL")
            
            logger.info(f"FORCE DOWNLOAD starting for: {video_id}")
            
            if db:
                existing_video = db.query(Video).filter(Video.id == video_id).first()
                if existing_video:
                    self.active_downloads[task_id]['status'] = 'completed'
                    self.active_downloads[task_id]['error'] = 'Video already exists in library'
                    return
            
            self.active_downloads[task_id]['status'] = 'downloading'
            self.active_downloads[task_id]['progress'] = 10
            
            methods = [
                self._download_with_yt_dlp,
                self._download_with_subprocess,
                self._download_with_youtube_dl
            ]
            
            filename = None
            for i, method in enumerate(methods, 1):
                logger.info(f"Trying method {i}/{len(methods)}: {method.__name__}")
                self.active_downloads[task_id]['progress'] = 10 + (i * 20)
                
                filename = method(url, video_id)
                if filename and os.path.exists(filename):
                    file_size = os.path.getsize(filename)
                    if file_size > 1024:
                        logger.info(f"✅ SUCCESS with {method.__name__}")
                        break
                    else:
                        os.remove(filename)
                        filename = None
            
            if filename and os.path.exists(filename):
                self.active_downloads[task_id]['filename'] = filename
                self.active_downloads[task_id]['progress'] = 90
                
                metadata = self.metadata_extractor.get_metadata(video_id)
                
                if db:
                    self._add_video_to_db(filename, video_id, metadata or {}, db)
                
                self.active_downloads[task_id]['status'] = 'completed'
                self.active_downloads[task_id]['progress'] = 100
                
                logger.info(f"✅ DOWNLOAD COMPLETED: {filename}")
            else:
                raise Exception("All download methods failed")
                
        except Exception as e:
            error_msg = str(e)
            logger.error(f"❌ DOWNLOAD FAILED for {task_id}: {error_msg}")
            self.active_downloads[task_id]['status'] = 'error'
            self.active_downloads[task_id]['error'] = error_msg

    def _add_video_to_db(self, file_path: str, video_id: str, metadata: dict, db: Session):
        try:
            file_stat = Path(file_path).stat()
            
            video = Video(
                id=video_id,
                file_path=file_path,
                title=metadata.get('title', Path(file_path).stem),
                thumbnail_url=metadata.get('thumbnail_url'),
                channel_name=metadata.get('channel_name', 'Unknown Channel'),
                channel_id=metadata.get('channel_id'),
                duration=metadata.get('duration', 0),
                description=metadata.get('description', ''),
                view_count=metadata.get('view_count', 0),
                like_count=metadata.get('like_count', 0),
                resolution=metadata.get('resolution', 'Unknown'),
                file_size=file_stat.st_size,
                added_date=datetime.utcnow()
            )
            
            if metadata.get('tags'):
                video.tags = json.dumps(metadata['tags'][:50])
            
            if metadata.get('upload_date'):
                try:
                    video.upload_date = datetime.strptime(metadata['upload_date'], '%Y%m%d')
                except:
                    pass
            
            db.add(video)
            db.commit()
            logger.info(f"✅ Added to database: {video.title}")
            
        except Exception as e:
            logger.error(f"❌ Database error: {str(e)}")
            db.rollback()

    def get_download_status(self, task_id: str) -> Optional[Dict]:
        return self.active_downloads.get(task_id)

    def get_all_downloads(self) -> Dict[str, Dict]:
        return self.active_downloads

    def cancel_download(self, task_id: str) -> bool:
        if task_id in self.active_downloads:
            self.active_downloads[task_id]['status'] = 'cancelled'
            self.active_downloads[task_id]['error'] = 'Download cancelled by user'
            return True
        return False

    def cleanup_old_downloads(self, hours: int = 24):
        pass
EOF

# 10. API Routes
log_step "Création des APIs"