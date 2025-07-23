import React, { useState, useEffect } from 'react';
import { FaTimes, FaDownload, FaSpinner, FaCheck, FaExclamationTriangle } from 'react-icons/fa';
import { videoService } from '../services/api';
import { formatDuration } from '../utils/formatters';

const DownloadModal = ({ isOpen, onClose, onDownloadComplete }) => {
  const [url, setUrl] = useState('');
  const [quality, setQuality] = useState('best');
  const [loading, setLoading] = useState(false);
  const [metadata, setMetadata] = useState(null);
  const [downloading, setDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!isOpen) {
      // Reset state when modal closes
      setUrl('');
      setQuality('best');
      setMetadata(null);
      setDownloading(false);
      setDownloadProgress(null);
      setError('');
    }
  }, [isOpen]);

  useEffect(() => {
    let interval;
    if (downloadProgress?.task_id && downloading) {
      interval = setInterval(async () => {
        try {
          const response = await videoService.getDownloadStatus(downloadProgress.task_id);
          setDownloadProgress(response.data);
          
          if (response.data.status === 'completed') {
            setDownloading(false);
            clearInterval(interval);
            setTimeout(() => {
              onDownloadComplete();
              onClose();
            }, 2000);
          } else if (response.data.status === 'error') {
            setDownloading(false);
            setError(response.data.error || 'Download failed');
            clearInterval(interval);
          }
        } catch (err) {
          console.error('Error checking download status:', err);
        }
      }, 1000);
    }
    return () => clearInterval(interval);
  }, [downloadProgress?.task_id, downloading, onClose, onDownloadComplete]);

  const handleUrlChange = async (e) => {
    const newUrl = e.target.value;
    setUrl(newUrl);
    setError('');
    
    // Auto-fetch metadata when valid YouTube URL is entered
    if (newUrl.match(/^(https?:\/\/)?(www\.)?(youtube\.com|youtu\.be)\/.+$/)) {
      setLoading(true);
      try {
        const response = await videoService.getVideoMetadata({ url: newUrl });
        setMetadata(response.data);
      } catch (err) {
        console.error('Error fetching metadata:', err);
      } finally {
        setLoading(false);
      }
    } else {
      setMetadata(null);
    }
  };

  const handleDownload = async () => {
    if (!url) return;
    
    setError('');
    setDownloading(true);
    try {
      const response = await videoService.downloadVideo({ url, quality });
      setDownloadProgress({ task_id: response.data.task_id, status: 'pending', progress: 0 });
    } catch (err) {
      setError(err.response?.data?.detail || 'Failed to start download');
      setDownloading(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-gray-900 rounded-lg w-full max-w-2xl max-h-[90vh] overflow-hidden">
        <div className="flex items-center justify-between p-4 border-b border-gray-700">
          <h2 className="text-xl font-semibold flex items-center">
            <FaDownload className="mr-2" />
            Download YouTube Video
          </h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white transition"
            disabled={downloading}
          >
            <FaTimes />
          </button>
        </div>
        
        <div className="p-6">
          {/* URL Input */}
          <div className="mb-6">
            <label className="block text-sm font-medium mb-2">YouTube URL</label>
            <input
              type="text"
              value={url}
              onChange={handleUrlChange}
              placeholder="https://www.youtube.com/watch?v=..."
              className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500"
              disabled={downloading}
            />
          </div>

          {/* Video Preview */}
          {loading && (
            <div className="flex items-center justify-center py-8">
              <FaSpinner className="animate-spin text-2xl" />
            </div>
          )}
          
          {metadata && !loading && (
            <div className="mb-6 bg-gray-800 rounded-lg p-4">
              <div className="flex">
                <img
                  src={metadata.thumbnail}
                  alt={metadata.title}
                  className="w-32 h-18 object-cover rounded"
                />
                <div className="ml-4 flex-1">
                  <h3 className="font-semibold line-clamp-2">{metadata.title}</h3>
                  <p className="text-sm text-gray-400 mt-1">
                    {metadata.uploader} • {formatDuration(metadata.duration)}
                  </p>
                  {metadata.view_count && (
                    <p className="text-xs text-gray-500 mt-1">
                      {metadata.view_count.toLocaleString()} views
                    </p>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Quality Selection */}
          {metadata && metadata.formats && (
            <div className="mb-6">
              <label className="block text-sm font-medium mb-2">Quality</label>
              <select
                value={quality}
                onChange={(e) => setQuality(e.target.value)}
                className="w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-2 focus:outline-none focus:border-blue-500"
                disabled={downloading}
              >
                <option value="best">Best Quality</option>
                {metadata.formats.map((format) => (
                  <option key={format.format_id} value={format.resolution}>
                    {format.resolution} ({format.ext})
                  </option>
                ))}
                <option value="audio">Audio Only (MP3)</option>
              </select>
            </div>
          )}

          {/* Download Progress */}
          {downloading && downloadProgress && (
            <div className="mb-6">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm">
                  {downloadProgress.status === 'downloading' ? 'Downloading...' : 
                   downloadProgress.status === 'processing' ? 'Processing...' :
                   downloadProgress.status === 'completed' ? 'Completed!' : 
                   'Preparing...'}
                </span>
                {downloadProgress.speed && (
                  <span className="text-sm text-gray-400">
                    {downloadProgress.speed} • ETA: {downloadProgress.eta}
                  </span>
                )}
              </div>
              <div className="w-full bg-gray-700 rounded-full h-2">
                <div
                  className={`h-2 rounded-full transition-all duration-300 ${
                    downloadProgress.status === 'completed' ? 'bg-green-600' : 'bg-blue-600'
                  }`}
                  style={{ width: `${downloadProgress.progress || 0}%` }}
                />
              </div>
              {downloadProgress.status === 'completed' && (
                <div className="mt-2 flex items-center text-green-500">
                  <FaCheck className="mr-2" />
                  Download completed successfully!
                </div>
              )}
            </div>
          )}

          {/* Error Message */}
          {error && (
            <div className="mb-6 p-3 bg-red-900 bg-opacity-50 border border-red-700 rounded-lg flex items-center">
              <FaExclamationTriangle className="mr-2 text-red-500" />
              <span className="text-sm">{error}</span>
            </div>
          )}

          {/* Action Buttons */}
          <div className="flex justify-end space-x-3">
            <button
              onClick={onClose}
              className="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg transition"
              disabled={downloading}
            >
              Cancel
            </button>
            <button
              onClick={handleDownload}
              disabled={!url || !metadata || downloading}
              className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition disabled:opacity-50 disabled:cursor-not-allowed flex items-center"
            >
              {downloading ? (
                <>
                  <FaSpinner className="animate-spin mr-2" />
                  Downloading...
                </>
              ) : (
                <>
                  <FaDownload className="mr-2" />
                  Download
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default DownloadModal;