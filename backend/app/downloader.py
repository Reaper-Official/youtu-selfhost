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
import sys

# Désactiver SSL et warnings
ssl._create_default_https_context = ssl._create_unverified_context
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

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
        """Extraire l'ID de la vidéo depuis l'URL YouTube"""
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
        """Méthode 1: yt-dlp avec toutes les options SSL désactivées"""
        try:
            import yt_dlp
            
            output_template = os.path.join(self.download_path, f"%(title)s-{video_id}.%(ext)s")
            
            ydl_opts = {
                'outtmpl': output_template,
                'progress_hooks': [self._progress_hook(video_id)],
                'format': 'best[ext=mp4]/best',
                'merge_output_format': 'mp4',
                
                # SSL complètement désactivé
                'no_check_certificate': True,
                'prefer_insecure': True,
                
                # Robustesse
                'socket_timeout': 60,
                'retries': 10,
                'fragment_retries': 10,
                
                # Headers
                'user_agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'referer': 'https://www.youtube.com/',
                
                # Extracteur
                'extractor_args': {
                    'youtube': {
                        'player_client': ['android', 'web', 'ios'],
                        'skip': ['hls']
                    }
                },
                
                # Logging
                'quiet': False,
                'no_warnings': False,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                logger.info(f"Downloading with yt-dlp: {video_id}")
                ydl.download([url])
                
                # Chercher le fichier téléchargé
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
        """Méthode 2: yt-dlp via subprocess avec variables d'environnement"""
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
        """Méthode 3: youtube-dl en fallback"""
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
        """Démarrer le téléchargement d'une vidéo et retourner l'ID de la tâche"""
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
        """Fonction de téléchargement avec plusieurs méthodes de fallback"""
        try:
            video_id = self._get_video_id_from_url(url)
            if not video_id:
                raise ValueError("Could not extract video ID from URL")
            
            logger.info(f"FORCE DOWNLOAD starting for: {video_id}")
            
            # Vérifier si existe déjà
            if db:
                existing_video = db.query(Video).filter(Video.id == video_id).first()
                if existing_video:
                    self.active_downloads[task_id]['status'] = 'completed'
                    self.active_downloads[task_id]['error'] = 'Video already exists in library'
                    return
            
            self.active_downloads[task_id]['status'] = 'downloading'
            self.active_downloads[task_id]['progress'] = 10
            
            # Essayer les différentes méthodes
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
                    if file_size > 1024:  # Au moins 1KB
                        logger.info(f"✅ SUCCESS with {method.__name__}")
                        break
                    else:
                        os.remove(filename)
                        filename = None
            
            if filename and os.path.exists(filename):
                self.active_downloads[task_id]['filename'] = filename
                self.active_downloads[task_id]['progress'] = 90
                
                # Récupérer les métadonnées
                metadata = self.metadata_extractor.get_metadata(video_id)
                
                # Ajouter à la base de données
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
        """Ajouter la vidéo téléchargée à la base de données"""
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