/** @type {import('next').NextConfig} */
const nextConfig = {
  // Output standalone for Docker deployment
  output: 'standalone',

  // Environment variables
  env: {
    NEXT_PUBLIC_APP_NAME: process.env.NEXT_PUBLIC_APP_NAME,
  },

  // Image optimization
  images: {
    unoptimized: true, // Disable image optimization for Docker
  },

  // TypeScript strict mode
  typescript: {
    ignoreBuildErrors: false,
  },

  // Webpack configuration for path aliases
  webpack: (config, { buildId, dev, isServer, defaultLoaders, webpack }) => {
    // Add path aliases
    config.resolve.alias = {
      ...config.resolve.alias,
      '@': require('path').resolve(__dirname, 'app/src'),
    };

    return config;
  },
}

module.exports = nextConfig