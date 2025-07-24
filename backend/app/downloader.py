import yt_dlp
import os
import uuid
import glob
from typing import Dict, Optional
from pathlib import Path
import asyncio
from concurrent.futures import ThreadPoolExecutor
import logging
from datetime import datetime
from sqlalchemy.orm import Session
from .models import Video
from .utils.metadata import MetadataExtractor
import json

logger = logging.getLogger(__name__)

class VideoDownloader:
    def __init__(self, download_path: str):
        self.download_path = download_path
        self.active_downloads: Dict[str, Dict] = {}
        self.executor = ThreadPoolExecutor(max_workers=3)
        self.metadata_extractor = MetadataExtractor()
        
        # Créer le dossier de téléchargement s'il n'existe pas
        Path(self.download_path).mkdir(parents=True, exist_ok=True)
        
    def _progress_hook(self, task_id: str):
        """Hook pour suivre la progression du téléchargement"""
        def hook(d):
            try:
                if d['status'] == 'downloading':
                    # Calculer la progression
                    downloaded = d.get('downloaded_bytes', 0)
                    total = d.get('total_bytes') or d.get('total_bytes_estimate', 0)
                    
                    if total > 0:
                        progress = (downloaded / total) * 100
                    else:
                        # Si pas de taille totale, utiliser le fragment
                        progress = d.get('fragment_index', 0) * 10  # Estimation
                    
                    # Récupérer la vitesse et l'ETA
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
        """Extraire l'ID de la vidéo depuis l'URL YouTube"""
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': True
        }
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                return info.get('id')
        except Exception as e:
            logger.error(f"Error extracting video ID: {str(e)}")
            return None

    async def download_video(self, url: str, quality: str = "best", db: Session = None) -> str:
        """Démarrer le téléchargement d'une vidéo et retourner l'ID de la tâche"""
        task_id = str(uuid.uuid4())
        
        # Initialiser le statut du téléchargement
        self.active_downloads[task_id] = {
            'task_id': task_id,
            'status': 'pending',
            'progress': 0,
            'speed': None,
            'eta': None,
            'filename': None,
            'error': None
        }
        
        # Démarrer le téléchargement en arrière-plan
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
        """Fonction de téléchargement synchrone exécutée dans un thread"""
        try:
            # Extraire l'ID de la vidéo
            video_id = self._get_video_id_from_url(url)
            if not video_id:
                raise ValueError("Could not extract video ID from URL")
            
            logger.info(f"Starting download for video ID: {video_id}")
            
            # Vérifier si la vidéo existe déjà
            if db:
                existing_video = db.query(Video).filter(Video.id == video_id).first()
                if existing_video:
                    self.active_downloads[task_id]['status'] = 'completed'
                    self.active_downloads[task_id]['error'] = 'Video already exists in library'
                    logger.info(f"Video {video_id} already exists")
                    return
            
            # Configurer les options de téléchargement
            # Configurer les options de téléchargement
# Configurer les options de téléchargement
            ydl_opts = {
                'outtmpl': os.path.join(self.download_path, '%(title)s-%(id)s.%(ext)s'),
                'progress_hooks': [self._progress_hook(task_id)],
                'quiet': False,
                'no_warnings': False,
                # Options pour contourner les restrictions
                'format': 'best[ext=mp4]/best',  # Préférer MP4
                'merge_output_format': 'mp4',
                'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'referer': 'https://www.youtube.com/',
                'nocheckcertificate': True,
                'prefer_insecure': False,  # Changé à False pour plus de sécurité
                'no_warnings': True,
                'logtostderr': False,
                'quiet': True,
                'no_progress': False,
                'extractor_args': {'youtube': {'player_client': ['android', 'web']}},
                # Options supplémentaires pour la stabilité
                'socket_timeout': 30,
                'retries': 3,
                'fragment_retries': 3,
            }
            
            # Gérer la qualité demandée
            if quality != "best":
                if quality == "audio":
                    ydl_opts['format'] = 'bestaudio/best'
                    ydl_opts['postprocessors'] = [{
                        'key': 'FFmpegExtractAudio',
                        'preferredcodec': 'mp3',
                        'preferredquality': '192',
                    }]
                else:
                    # Essayer d'obtenir la qualité spécifique
                    height = quality.replace('p', '')
                    ydl_opts['format'] = f'best[height<={height}]/best'
            
            # Télécharger la vidéo
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                logger.info(f"Downloading video {video_id}...")
                info = ydl.extract_info(url, download=True)
                
                # Trouver le fichier téléchargé
                # yt-dlp peut changer l'extension, donc on cherche avec l'ID
                pattern = os.path.join(self.download_path, f"*{video_id}*")
                downloaded_files = glob.glob(pattern)
                
                if downloaded_files:
                    # Prendre le fichier le plus récent
                    filename = max(downloaded_files, key=os.path.getctime)
                    logger.info(f"Found downloaded file: {filename}")
                else:
                    # Fallback : essayer de reconstruire le nom
                    filename = ydl.prepare_filename(info)
                    # Vérifier différentes extensions possibles
                    for ext in ['.mp4', '.webm', '.mkv', '.m4a', '.mp3']:
                        test_file = filename.rsplit('.', 1)[0] + ext
                        if os.path.exists(test_file):
                            filename = test_file
                            break
                
                if not os.path.exists(filename):
                    raise FileNotFoundError(f"Downloaded file not found: {filename}")
                
                self.active_downloads[task_id]['filename'] = filename
                logger.info(f"Download completed: {filename}")
                
                # Ajouter à la base de données
                if db and os.path.exists(filename):
                    self._add_video_to_db(filename, video_id, info, db)
                
                self.active_downloads[task_id]['status'] = 'completed'
                self.active_downloads[task_id]['progress'] = 100
                
        except Exception as e:
            error_msg = str(e)
            logger.error(f"Download error for task {task_id}: {error_msg}")
            self.active_downloads[task_id]['status'] = 'error'
            self.active_downloads[task_id]['error'] = error_msg

    def _add_video_to_db(self, file_path: str, video_id: str, info: dict, db: Session):
        """Ajouter la vidéo téléchargée à la base de données"""
        try:
            file_stat = Path(file_path).stat()
            
            # Créer l'entrée vidéo
            video = Video(
                id=video_id,
                file_path=file_path,  # Chemin complet
                title=info.get('title', 'Unknown Title'),
                thumbnail_url=info.get('thumbnail'),
                channel_name=info.get('uploader', 'Unknown Channel'),
                channel_id=info.get('channel_id'),
                duration=info.get('duration', 0),
                description=info.get('description', ''),
                view_count=info.get('view_count', 0),
                like_count=info.get('like_count', 0),
                resolution=f"{info.get('width', 0)}x{info.get('height', 0)}",
                file_size=file_stat.st_size,
                added_date=datetime.utcnow()
            )
            
            # Gérer les tags
            if info.get('tags'):
                video.tags = json.dumps(info['tags'][:50])  # Limiter à 50 tags
            
            # Gérer la date d'upload
            if info.get('upload_date'):
                try:
                    video.upload_date = datetime.strptime(info['upload_date'], '%Y%m%d')
                except:
                    pass
            
            db.add(video)
            db.commit()
            logger.info(f"Added video to database: {video.title} (ID: {video_id})")
            
        except Exception as e:
            logger.error(f"Error adding video to database: {str(e)}")
            db.rollback()

    def get_download_status(self, task_id: str) -> Optional[Dict]:
        """Obtenir le statut d'un téléchargement"""
        return self.active_downloads.get(task_id)

    def get_all_downloads(self) -> Dict[str, Dict]:
        """Obtenir tous les téléchargements actifs"""
        return self.active_downloads

    def cancel_download(self, task_id: str) -> bool:
        """Annuler un téléchargement"""
        if task_id in self.active_downloads:
            self.active_downloads[task_id]['status'] = 'cancelled'
            self.active_downloads[task_id]['error'] = 'Download cancelled by user'
            # TODO: Implémenter l'arrêt réel du processus yt-dlp
            return True
        return False

    def cleanup_old_downloads(self, hours: int = 24):
        """Nettoyer les anciens téléchargements de la mémoire"""
        # TODO: Implémenter le nettoyage des téléchargements terminés depuis X heures
        pass