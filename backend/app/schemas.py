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
