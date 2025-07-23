import React, { useEffect } from 'react';
import ReactPlayer from 'react-player/file';
import { FaTimes } from 'react-icons/fa';
import { formatDate, formatViews } from '../utils/formatters';

const VideoPlayer = ({ video, onClose, onWatched }) => {
  useEffect(() => {
    // Mark as watched when video opens
    if (video && !video.watched) {
      onWatched(video.id);
    }
  }, [video, onWatched]);

  if (!video) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-90 z-50 flex items-center justify-center p-4">
      <div className="bg-youtube-dark rounded-lg w-full max-w-6xl max-h-[90vh] overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-gray-800">
          <h2 className="text-xl font-semibold truncate">{video.title}</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white transition"
          >
            <FaTimes className="text-xl" />
          </button>
        </div>
        
        <div className="flex flex-col lg:flex-row">
          <div className="flex-1">
            <div className="aspect-video bg-black">
              <ReactPlayer
                url={`/media/${video.file_path}`}
                controls
                width="100%"
                height="100%"
                playing
              />
            </div>
          </div>
          
          <div className="lg:w-96 p-4 border-l border-gray-800 overflow-y-auto max-h-[60vh]">
            <div className="space-y-4">
              <div>
                <h3 className="text-lg font-semibold">{video.channel_name}</h3>
                <p className="text-gray-400 text-sm">{formatViews(video.view_count)}</p>
                <p className="text-gray-400 text-sm">Uploaded {formatDate(video.upload_date)}</p>
              </div>
              
              {video.description && (
                <div>
                  <h4 className="font-semibold mb-2">Description</h4>
                  <p className="text-sm text-gray-300 whitespace-pre-wrap">{video.description}</p>
                </div>
              )}
              
              <div>
                <h4 className="font-semibold mb-2">File Info</h4>
                <div className="text-sm text-gray-400 space-y-1">
                  <p>Resolution: {video.resolution || 'Unknown'}</p>
                  <p>Size: {video.file_size ? `${(video.file_size / 1024 / 1024).toFixed(2)} MB` : 'Unknown'}</p>
                  <p>Added: {formatDate(video.added_date)}</p>
                  <p>Local views: {video.local_views}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VideoPlayer;