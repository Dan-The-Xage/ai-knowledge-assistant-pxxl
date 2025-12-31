/** @type {import('next').NextConfig} */
const nextConfig = {
  // Configure the app directory (moved from frontend/)
  experimental: {
    appDir: 'app',
  },

  // Output standalone for Docker deployment
  output: 'standalone',

  // Disable telemetry
  telemetry: false,

  // Environment variables
  env: {
    NEXT_PUBLIC_APP_NAME: process.env.NEXT_PUBLIC_APP_NAME,
  },

  // Image optimization
  images: {
    unoptimized: true, // Disable image optimization for Docker
  },
}

module.exports = nextConfig