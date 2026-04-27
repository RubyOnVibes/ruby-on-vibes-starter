import react from '@vitejs/plugin-react-swc'
import { defineConfig } from 'vite'
import tailwindcss from '@tailwindcss/vite'
import RubyPlugin from 'vite-plugin-ruby'
import path from 'path'

export default defineConfig({
  plugins: [
    react(),
    RubyPlugin(),
    tailwindcss(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'app/javascript')
    },
  },
  // Allow Vite to prebundle React/ReactDOM for faster dev and consistent bundling
  optimizeDeps: {},
  // SSR Configuration: Bundle all dependencies (no externals)
  // This ensures the SSR bundle is self-contained and doesn't need node_modules at runtime
  ssr: {
    noExternal: true, // Bundle ALL dependencies into SSR bundle
  },
})
