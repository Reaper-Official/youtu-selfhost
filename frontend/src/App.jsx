import React, { useState, useEffect } from 'react';
import Header from './components/Header';
import VideoGrid from './components/VideoGrid';
import VideoPlayer from './components/VideoPlayer';
import DownloadModal from './components/DownloadModal';
import { videoService } from './services/api';

function App() {
  const [videos, setVideos] = useState([]);
  const [selectedVideo, setSelectedVideo] = useState(null);
  const [isScanning, setIsScanning] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [showDownloadModal, setShowDownloadModal] = useState(false);

  useEffect(() => {
    loadVideos();
  }, [searchQuery]);

  const loadVideos = async () => {
    try {
      setLoading(true);
      const response = await videoService.getVideos({
        search: searchQuery,
        limit: 100
      });
      setVideos(response.data);
    } catch (error) {
      console.error('Error loading videos:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSearch = (query) => {
    setSearchQuery(query);
  };

  const handleScan = async () => {
    try {
      setIsScanning(true);
      const response = await videoService.scanVideos({ recursive: true });
      console.log('Scan results:', response.data);
      await loadVideos(); // Reload videos after scan
    } catch (error) {
      console.error('Error scanning videos:', error);
    } finally {
      setIsScanning(false);
    }
  };

  const handleVideoClick = (video) => {
    setSelectedVideo(video);
  };

  const handleClosePlayer = () => {
    setSelectedVideo(null);
    loadVideos(); // Reload to update watched status
  };

  const handleVideoWatched = async (videoId) => {
    try {
      await videoService.updateVideo(videoId, {
        watched: true,
        last_watched: new Date().toISOString()
      });
    } catch (error) {
      console.error('Error updating video:', error);
    }
  };

  const handleDownload = () => {
    setShowDownloadModal(true);
  };

  const handleDownloadComplete = () => {
    loadVideos();
  };

  return (
    <div className="min-h-screen bg-youtube-dark">
      <Header 
        onSearch={handleSearch}
        onScan={handleScan}
        onDownload={handleDownload}
        isScanning={isScanning}
      />
      
      <main className="max-w-7xl mx-auto px-4 py-6">
        {loading ? (
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-white"></div>
          </div>
        ) : (
          <VideoGrid videos={videos} onVideoClick={handleVideoClick} />
        )}
      </main>
      
      {selectedVideo && (
        <VideoPlayer
          video={selectedVideo}
          onClose={handleClosePlayer}
          onWatched={handleVideoWatched}
        />
      )}
      
      <DownloadModal
        isOpen={showDownloadModal}
        onClose={() => setShowDownloadModal(false)}
        onDownloadComplete={handleDownloadComplete}
      />
    </div>
  );
}

export default App;