import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte()],
  build: { license: { fileName: 'frontend-licenses.md' } },
  server: {
    host: '127.0.0.1',
    port: 1420,
    strictPort: true,
  },
});
