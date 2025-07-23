import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000/api';

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
};

export default api;
