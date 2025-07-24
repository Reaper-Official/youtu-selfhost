import yt_dlp
import re
import ssl
import urllib3
from typing import Optional, Dict
import logging

# Désactiver SSL globalement
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
        """Extract YouTube video ID from filename"""
        patterns = [
            r'[-_]([a-zA-Z0-9_-]{11})(?:\.|$)',  # ID at the end
            r'\[([a-zA-Z0-9_-]{11})\]',           # ID in brackets
            r'\(([a-zA-Z0-9_-]{11})\)',           # ID in parentheses
        ]
        
        for pattern in patterns:
            match = re.search(pattern, filename)
            if match:
                return match.group(1)
        return None
    
    def get_metadata(self, video_id: str) -> Optional[Dict]:
        """Fetch metadata from YouTube with SSL disabled"""
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