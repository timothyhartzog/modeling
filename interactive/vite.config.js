import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'

export default defineConfig({
  plugins: [react()],
  // base matches the GitHub Pages subpath: https://timothyhartzog.github.io/modeling/interactive/
  // Change to '/' if hosting at domain root or a different subpath.
  base: '/modeling/interactive/',
  build: {
    outDir: resolve(__dirname, '../output/_site/interactive'),
    rollupOptions: {
      input: {
        main:                resolve(__dirname, 'index.html'),
        'concept-map':       resolve(__dirname, 'pages/concept-map.html'),
        'phase-portrait':    resolve(__dirname, 'pages/phase-portrait.html'),
        'gradient-descent':  resolve(__dirname, 'pages/gradient-descent.html'),
        'distribution':      resolve(__dirname, 'pages/distribution.html'),
        'quiz':              resolve(__dirname, 'pages/quiz.html'),
        'proof-explorer':    resolve(__dirname, 'pages/proof-explorer.html'),
      }
    }
  },
  server: {
    port: 5173,
    open: true
  }
})
