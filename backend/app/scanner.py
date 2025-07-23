import os
from pathlib import Path
from typing import List, Dict
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
        """Scan directory for video files"""
        results = {
            'videos_found': 0,
            'videos_added': 0,
            'errors': []
        }
        
        path = Path(directory)
        if not path.exists():
            results['errors'].append(f"Directory {directory} does not exist")
            return results
        
        # Get all video files
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
        """Process a single video file"""
        # Extract video ID from filename
        video_id = self.metadata_extractor.extract_video_id(file_path.name)
        if not video_id:
            raise ValueError("Could not extract YouTube ID from filename")
        
        # Check if video already exists
        existing_video = self.db.query(Video).filter(Video.id == video_id).first()
        if existing_video:
            logger.info(f"Video {video_id} already in database")
            return
        
        # Get file info
        file_stat = file_path.stat()
        
        # Create video entry with basic info
        video = Video(
            id=video_id,
            file_path=str(file_path),
            file_size=file_stat.st_size,
            added_date=datetime.utcnow()
        )
        
        # Try to fetch metadata from YouTube
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
            # Use filename as title if metadata fetch fails
            video.title = file_path.stem
        
        self.db.add(video)
        logger.info(f"Added video: {video.title or video_id}")
