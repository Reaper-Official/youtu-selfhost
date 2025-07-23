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
    duration = Column(Integer)  # in seconds
    upload_date = Column(DateTime)
    description = Column(Text)
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    tags = Column(Text)  # JSON string
    resolution = Column(String)
    file_size = Column(Integer)  # in bytes
    added_date = Column(DateTime, default=datetime.utcnow)
    last_watched = Column(DateTime, nullable=True)
    watched = Column(Boolean, default=False)
    local_views = Column(Integer, default=0)
