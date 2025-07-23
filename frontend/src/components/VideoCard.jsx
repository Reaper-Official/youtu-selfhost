import React from 'react';
import { FaPlay, FaCheck } from 'react-icons/fa';
import { formatDuration, formatDate } from '../utils/formatters';

const VideoCard = ({ video, onClick }) => {
  return (
    <div
      className="bg-gray-900 rounded-lg overflow-hidden cursor-pointer transform transition duration-200 hover:scale-105 hover:shadow-xl"
      onClick={() => onClick(video)}
    >
      <div className="relative aspect-video">
        <img
          src={video.thumbnail_url || '/placeholder-thumbnail.jpg'}
          alt={video.title}
          className="w-full h-full object-cover"
        />
        <div className="absolute bottom-2 right-2 bg-black bg-opacity-80 px-2 py-1 rounded text-xs">
          {formatDuration(video.duration)}
        </div>
        {video.watched && (
          <div className="absolute top-2 right-2 bg-green-600 p-1 rounded-full">
            <FaCheck className="text-xs" />
          </div>
        )}
        <div className="absolute inset-0 bg-black bg-opacity-0 hover:bg-opacity-30 flex items-center justify-center opacity-0 hover:opacity-100 transition duration-200">
          <FaPlay className="text-4xl" />
        </div>
      </div>
      
      <div className="p-3">
        <h3 className="font-semibold line-clamp-2 mb-1">{video.title || 'Untitled Video'}</h3>
        <p className="text-sm text-gray-400">{video.channel_name || 'Unknown Channel'}</p>
        <p className="text-xs text-gray-500 mt-1">{formatDate(video.upload_date)}</p>
      </div>
    </div>
  );
};

export default VideoCard;