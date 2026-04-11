import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../output/_site/interactive',
    rollupOptions: {
      input: {
        'index': './index.html',
        'concept-map': './pages/concept-map.html',
        'phase-portrait': './pages/phase-portrait.html',
        'gradient-descent': './pages/gradient-descent.html',
        'distribution': './pages/distribution.html',
        'quiz': './pages/quiz.html',
        'proof-explorer': './pages/proof-explorer.html',
      }
    }
  }
})
