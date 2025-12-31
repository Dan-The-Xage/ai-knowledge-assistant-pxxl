import { NextRequest, NextResponse } from 'next/server';

/**
 * Health Check API Endpoint
 * Used by Pxxl.app for deployment health checks
 */

export async function GET(request: NextRequest) {
  try {
    // Basic health check
    const healthData = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      services: {
        frontend: 'operational',
        supabase: process.env.NEXT_PUBLIC_SUPABASE_URL ? 'configured' : 'not_configured',
        huggingface: process.env.NEXT_PUBLIC_HF_API_TOKEN ? 'configured' : 'not_configured',
      },
      environment: {
        node_env: process.env.NODE_ENV,
        next_public_app_name: process.env.NEXT_PUBLIC_APP_NAME,
      }
    };

    return NextResponse.json(healthData, { status: 200 });
  } catch (error) {
    console.error('Health check error:', error);
    return NextResponse.json({
      status: 'unhealthy',
      error: 'Health check failed',
      timestamp: new Date().toISOString(),
    }, { status: 500 });
  }
}
