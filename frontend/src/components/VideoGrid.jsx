import React from 'react';
import VideoCard from './VideoCard';

const VideoGrid = ({ videos, onVideoClick }) => {
  if (videos.length === 0) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-gray-400">No videos found</p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
      {videos.map((video) => (
        <VideoCard
          key={video.id}
          video={video}
          onClick={onVideoClick}
        />
      ))}
    </div>
  );
};

export default VideoGrid;