import yt_dlp
import os
import uuid
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
        
    def _progress_hook(self, task_id: str):
        def hook(d):
            if d['status'] == 'downloading':
                self.active_downloads[task_id].update({
                    'status': 'downloading',
                    'progress': d.get('downloaded_bytes', 0) / d.get('total_bytes', 1) * 100 if d.get('total_bytes') else 0,
                    'speed': d.get('speed_str', 'N/A'),
                    'eta': d.get('eta_str', 'N/A'),
                    'filename': d.get('filename', '')
                })
            elif d['status'] == 'finished':
                self.active_downloads[task_id].update({
                    'status': 'processing',
                    'progress': 100,
                    'filename': d.get('filename', '')
                })
        return hook

    def _get_video_id_from_url(self, url: str) -> Optional[str]:
        """Extract video ID from YouTube URL"""
        ydl_opts = {'quiet': True, 'no_warnings': True}
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                return info.get('id')
        except:
            return None

    async def download_video(self, url: str, quality: str = "best", db: Session = None) -> str:
        """Start a video download and return task ID"""
        task_id = str(uuid.uuid4())
        
        # Initialize download status
        self.active_downloads[task_id] = {
            'task_id': task_id,
            'status': 'pending',
            'progress': 0,
            'speed': None,
            'eta': None,
            'filename': None,
            'error': None
        }
        
        # Start download in background
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
        """Synchronous download function to run in thread"""
        try:
            # Get video ID first
            video_id = self._get_video_id_from_url(url)
            if not video_id:
                raise ValueError("Could not extract video ID from URL")
            
            # Check if video already exists in database
            if db:
                existing_video = db.query(Video).filter(Video.id == video_id).first()
                if existing_video:
                    self.active_downloads[task_id]['status'] = 'completed'
                    self.active_downloads[task_id]['error'] = 'Video already exists in library'
                    return
            
            # Configure download options
            ydl_opts = {
                'outtmpl': os.path.join(self.download_path, '%(title)s-%(id)s.%(ext)s'),
                'progress_hooks': [self._progress_hook(task_id)],
                'quiet': False,
                'no_warnings': False,
            }
            
            # Set quality options
            if quality != "best":
                if quality == "audio":
                    ydl_opts['format'] = 'bestaudio/best'
                    ydl_opts['postprocessors'] = [{
                        'key': 'FFmpegExtractAudio',
                        'preferredcodec': 'mp3',
                        'preferredquality': '192',
                    }]
                else:
                    # Try to get specific quality, fallback to best if not available
                    ydl_opts['format'] = f'best[height<={quality[:-1]}]/best'
            
            # Download the video
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                
                # Get the actual filename
                filename = ydl.prepare_filename(info)
                # Replace extension if needed
                if 'ext' in info:
                    base_filename = filename.rsplit('.', 1)[0]
                    filename = f"{base_filename}.{info['ext']}"
                
                self.active_downloads[task_id]['filename'] = filename
                
                # Add to database if db session provided
                if db and os.path.exists(filename):
                    self._add_video_to_db(filename, video_id, info, db)
                
                self.active_downloads[task_id]['status'] = 'completed'
                self.active_downloads[task_id]['progress'] = 100
                
        except Exception as e:
            logger.error(f"Download error for task {task_id}: {str(e)}")
            self.active_downloads[task_id]['status'] = 'error'
            self.active_downloads[task_id]['error'] = str(e)

    def _add_video_to_db(self, file_path: str, video_id: str, info: dict, db: Session):
        """Add downloaded video to database"""
        try:
            file_stat = Path(file_path).stat()
            
            video = Video(
                id=video_id,
                file_path=file_path,
                title=info.get('title'),
                thumbnail_url=info.get('thumbnail'),
                channel_name=info.get('uploader'),
                channel_id=info.get('channel_id'),
                duration=info.get('duration'),
                description=info.get('description'),
                view_count=info.get('view_count'),
                like_count=info.get('like_count'),
                resolution=f"{info.get('width')}x{info.get('height')}" if info.get('width') else None,
                file_size=file_stat.st_size,
                added_date=datetime.utcnow()
            )
            
            if info.get('tags'):
                video.tags = json.dumps(info['tags'])
            
            if info.get('upload_date'):
                try:
                    video.upload_date = datetime.strptime(info['upload_date'], '%Y%m%d')
                except:
                    pass
            
            db.add(video)
            db.commit()
            logger.info(f"Added downloaded video to database: {video.title}")
            
        except Exception as e:
            logger.error(f"Error adding video to database: {str(e)}")
            db.rollback()

    def get_download_status(self, task_id: str) -> Optional[Dict]:
        """Get status of a download task"""
        return self.active_downloads.get(task_id)

    def get_all_downloads(self) -> Dict[str, Dict]:
        """Get all active downloads"""
        return self.active_downloads

    def cancel_download(self, task_id: str) -> bool:
        """Cancel a download (not implemented yet)"""
        if task_id in self.active_downloads:
            # TODO: Implement actual cancellation
            self.active_downloads[task_id]['status'] = 'cancelled'
            return True
        return False