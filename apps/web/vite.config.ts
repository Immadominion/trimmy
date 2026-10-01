import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import {developmentApiPlugin} from './dev-api';
import {readFileSync} from 'node:fs';

// The app version usage events carry: the package version and, on Vercel, the commit.
const version = `${JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')).version}+${(process.env['VERCEL_GIT_COMMIT_SHA'] ?? 'local').slice(0, 7)}`;

export default defineConfig(({mode}) => ({
  plugins: [react(), developmentApiPlugin(loadEnv(mode, process.cwd(), 'TRIMMY_WEB_DEV_')['TRIMMY_WEB_DEV_API_URL'])],
  server: {host: '127.0.0.1', port: 4174, strictPort: true},
  preview: {host: '127.0.0.1', port: 4174, strictPort: true},
  build: {sourcemap: false},
  define: {__TRIMMY_WEB_VERSION__: JSON.stringify(version)},
}));
