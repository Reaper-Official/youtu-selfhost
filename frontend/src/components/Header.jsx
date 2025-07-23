import React from 'react';
import { FaYoutube, FaSync, FaDownload } from 'react-icons/fa';
import SearchBar from './SearchBar';

const Header = ({ onSearch, onScan, onDownload, isScanning }) => {
  return (
    <header className="bg-youtube-dark border-b border-gray-800 px-4 py-3">
      <div className="max-w-7xl mx-auto flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <FaYoutube className="text-youtube-red text-3xl" />
          <h1 className="text-xl font-bold">YouTube Library</h1>
        </div>
        
        <div className="flex-1 max-w-2xl mx-8">
          <SearchBar onSearch={onSearch} />
        </div>
        
        <div className="flex items-center space-x-3">
          <button
            onClick={onDownload}
            className="flex items-center space-x-2 bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded-lg transition duration-200"
          >
            <FaDownload />
            <span>Download</span>
          </button>
          
          <button
            onClick={onScan}
            disabled={isScanning}
            className="flex items-center space-x-2 bg-gray-800 hover:bg-gray-700 px-4 py-2 rounded-lg transition duration-200 disabled:opacity-50"
          >
            <FaSync className={`${isScanning ? 'animate-spin' : ''}`} />
            <span>{isScanning ? 'Scanning...' : 'Scan Library'}</span>
          </button>
        </div>
      </div>
    </header>
  );
};

export default Header;