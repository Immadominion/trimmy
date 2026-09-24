import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import {developmentApiPlugin} from './dev-api';

export default defineConfig(({mode}) => ({
  plugins: [react(), developmentApiPlugin(loadEnv(mode, process.cwd(), 'TRIMMY_WEB_DEV_')['TRIMMY_WEB_DEV_API_URL'])],
  server: {host: '127.0.0.1', port: 4174, strictPort: true},
  preview: {host: '127.0.0.1', port: 4174, strictPort: true},
  build: {sourcemap: false},
}));
