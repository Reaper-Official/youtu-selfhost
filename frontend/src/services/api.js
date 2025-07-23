import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || `http://${window.location.hostname}:8000/api`;

const api = axios.create({
  baseURL: API_BASE_URL,
});

export const videoService = {
  getVideos: (params) => api.get('/videos', { params }),
  getVideo: (id) => api.get(`/videos/${id}`),
  updateVideo: (id, data) => api.patch(`/videos/${id}`, data),
  deleteVideo: (id) => api.delete(`/videos/${id}`),
  getChannels: () => api.get('/channels'),
  scanVideos: (data) => api.post('/scan', data),
  
  // Download endpoints
  downloadVideo: (data) => api.post('/download', data),
  getDownloadStatus: (taskId) => api.get(`/download/${taskId}`),
  getAllDownloads: () => api.get('/downloads'),
  cancelDownload: (taskId) => api.delete(`/download/${taskId}`),
  getVideoMetadata: (data) => api.post('/download/metadata', data),
};

export default api;