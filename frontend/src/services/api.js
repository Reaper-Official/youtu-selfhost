import axios from 'axios';

// Configuration plus robuste de l'API
const getApiBaseUrl = () => {
  // En production, utiliser l'IP du serveur
  if (process.env.REACT_APP_API_URL) {
    return process.env.REACT_APP_API_URL;
  }
  
  // Fallback: utiliser l'hostname actuel
  const hostname = window.location.hostname;
  return `http://${hostname}:8000/api`;
};

const API_BASE_URL = getApiBaseUrl();

const api = axios.create({
  baseURL: API_BASE_URL,
  timeout: 30000, // 30 secondes de timeout
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  }
});

// Intercepteur pour gérer les erreurs
api.interceptors.response.use(
  (response) => response,
  (error) => {
    console.error('API Error:', error);
    if (error.code === 'ERR_NETWORK') {
      console.error('Network error - backend might be down or CORS issue');
    }
    return Promise.reject(error);
  }
);

// Intercepteur pour les requêtes
api.interceptors.request.use(
  (config) => {
    console.log(`API Call: ${config.method?.toUpperCase()} ${config.url}`);
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

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
  
  // Health check
  healthCheck: () => api.get('/health'),
};

export default api;