/**
 * AI Service for Hugging Face Inference API
 * Runs directly in the frontend for immediate AI responses
 */

export interface AIResponse {
  success: boolean;
  data?: any;
  error?: string;
  fallback?: string;
}

export interface DocumentChunk {
  id: string;
  content: string;
  metadata?: any;
}

class AIService {
  private hfToken: string;
  private baseUrl = 'https://api-inference.huggingface.co/models';

  constructor() {
    this.hfToken = process.env.NEXT_PUBLIC_HF_API_TOKEN || '';
    if (!this.hfToken) {
      console.warn('Hugging Face API token not configured');
    }
  }

  /**
   * Generate AI response using Mistral model
   */
  async generateResponse(message: string, context?: string): Promise<AIResponse> {
    try {
      if (!this.hfToken) {
        return {
          success: false,
          error: 'AI service not configured. Please check NEXT_PUBLIC_HF_API_TOKEN environment variable in Pxxl.app.'
        };
      }

      // Build prompt with context if available
      let prompt = message;
      if (context) {
        prompt = `<s>[INST] You are an AI assistant helping users with their documents. Use the following context to answer accurately. If the context doesn't contain relevant information, say so clearly.

Context: ${context}

Question: ${message}

Answer based only on the provided context. Be concise but helpful. [/INST]`;
      } else {
        prompt = `<s>[INST] You are a helpful AI Knowledge Assistant. Answer clearly and accurately: ${message} [/INST]`;
      }

      const response = await fetch(`${this.baseUrl}/mistralai/Mistral-7B-Instruct-v0.2`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.hfToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          inputs: prompt,
          parameters: {
            max_new_tokens: 512,
            temperature: 0.3,
            top_p: 0.95,
            do_sample: true,
            return_full_text: false,
          },
          options: {
            wait_for_model: true,
          },
        }),
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        return {
          success: false,
          error: `AI service error: ${response.status} - ${errorData.error || 'Unknown error'}`
        };
      }

      const data = await response.json();

      if (Array.isArray(data) && data.length > 0) {
        let generatedText = data[0].generated_text || '';

        // Clean up the response
        if (generatedText.includes('[/INST]')) {
          generatedText = generatedText.split('[/INST]')[1].trim();
        }

        // Remove any remaining prompt artifacts
        generatedText = generatedText.replace(/<s>|<\/s>|\[INST\]|\[\/INST\]/g, '').trim();

        return {
          success: true,
          data: {
            response: generatedText,
            model: 'mistralai/Mistral-7B-Instruct-v0.2',
            timestamp: new Date().toISOString(),
          }
        };
      }

      return {
        success: false,
        error: 'Unexpected response format from AI service'
      };

    } catch (error) {
      console.error('AI service error:', error);

      // Provide more specific error messages
      let errorMessage = 'Unknown error occurred';
      if (error instanceof TypeError && error.message.includes('fetch')) {
        errorMessage = 'Network error: Unable to connect to AI service. This may be due to CORS restrictions or network connectivity issues. Please check that NEXT_PUBLIC_HF_API_TOKEN is set in Pxxl.app environment variables.';
      } else if (error instanceof Error) {
        errorMessage = `AI service error: ${error.message}`;
      }

      // Provide a fallback helpful response
      const fallbackResponse = context
        ? `I apologize, but I'm currently unable to generate an AI response due to a technical issue. However, I can see you have document context available. Please try again in a moment, or feel free to ask specific questions about your documents.`
        : `I apologize, but I'm currently experiencing technical difficulties connecting to the AI service. Please try again in a moment, or check that the application is properly configured.`;

      return {
        success: false,
        error: errorMessage,
        fallback: fallbackResponse
      };
    }
  }

  /**
   * Generate embeddings for document chunks
   */
  async generateEmbeddings(text: string): Promise<AIResponse> {
    try {
      if (!this.hfToken) {
        return {
          success: false,
          error: 'AI service not configured. Please check API token.'
        };
      }

      const response = await fetch(`${this.baseUrl}/BAAI/bge-small-en-v1.5`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.hfToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          inputs: text.slice(0, 512), // Limit input length
          options: {
            wait_for_model: true,
          },
        }),
      });

      if (!response.ok) {
        return {
          success: false,
          error: `Embedding service error: ${response.status}`
        };
      }

      const embedding = await response.json();

      // Normalize the embedding
      const array = Array.isArray(embedding) ? embedding : embedding.embedding || [];
      const norm = Math.sqrt(array.reduce((sum: number, val: number) => sum + val * val, 0));
      const normalizedEmbedding = array.map((val: number) => val / norm);

      return {
        success: true,
        data: {
          embedding: normalizedEmbedding,
          model: 'BAAI/bge-small-en-v1.5',
          dimensions: normalizedEmbedding.length,
        }
      };

    } catch (error) {
      console.error('Embedding generation error:', error);
      return {
        success: false,
        error: `Embedding error: ${error instanceof Error ? error.message : 'Unknown error'}`
      };
    }
  }

  /**
   * Process document text and extract key information
   */
  async summarizeDocument(text: string): Promise<AIResponse> {
    const prompt = `<s>[INST] Summarize the following document in 2-3 sentences, highlighting the main points and key information:

${text.slice(0, 2000)}

Provide a clear, concise summary. [/INST]`;

    return this.generateResponse(prompt);
  }

  /**
   * Extract keywords from text
   */
  async extractKeywords(text: string): Promise<AIResponse> {
    const prompt = `<s>[INST] Extract 5-10 key keywords or phrases from the following text. Return them as a comma-separated list:

${text.slice(0, 1000)}

Keywords: [/INST]`;

    const response = await this.generateResponse(prompt);

    if (response.success && response.data?.response) {
      // Parse the keywords from the response
      const keywords = response.data.response
        .split(',')
        .map((k: string) => k.trim())
        .filter((k: string) => k.length > 0)
        .slice(0, 10);

      return {
        success: true,
        data: {
          keywords,
          count: keywords.length,
        }
      };
    }

    return response;
  }

  /**
   * Check if AI service is available
   */
  async isAvailable(): Promise<boolean> {
    if (!this.hfToken) return false;

    try {
      const response = await this.generateResponse('Hello');
      return response.success === true;
    } catch {
      return false;
    }
  }

  /**
   * Get service status and diagnostics
   */
  getStatus(): { configured: boolean; tokenPresent: boolean; message: string } {
    const tokenPresent = !!this.hfToken;
    const configured = tokenPresent && this.hfToken.length > 10;

    let message = '';
    if (!tokenPresent) {
      message = 'Hugging Face API token not found. Please set NEXT_PUBLIC_HF_API_TOKEN in Pxxl.app environment variables.';
    } else if (!configured) {
      message = 'Hugging Face API token appears to be invalid or too short.';
    } else {
      message = 'AI service appears to be configured correctly.';
    }

    return { configured, tokenPresent, message };
  }
}

// Export singleton instance
export const aiService = new AIService();
export default aiService;
