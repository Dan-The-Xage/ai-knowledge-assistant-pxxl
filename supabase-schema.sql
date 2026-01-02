-- ===========================================
-- AI Knowledge Assistant - Supabase Schema
-- ===========================================
-- This schema creates all necessary tables, indexes, and RLS policies
-- for the AI Knowledge Assistant application.

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector; -- For pgvector extension

-- ===========================================
-- USERS TABLE (extends Supabase auth.users)
-- ===========================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID DEFAULT auth.uid() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('super_admin', 'admin', 'user', 'guest')),
  department TEXT,
  job_title TEXT,
  is_active BOOLEAN DEFAULT TRUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- Create trigger to update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = TIMEZONE('utc'::text, NOW());
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ===========================================
-- DOCUMENTS TABLE
-- ===========================================
CREATE TABLE IF NOT EXISTS public.documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  filename TEXT NOT NULL,
  file_path TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  file_size BIGINT NOT NULL,
  uploaded_by UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  uploaded_by_email TEXT NOT NULL,
  project_id UUID,
  processing_status TEXT NOT NULL DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed')),
  extracted_text TEXT,
  embedding VECTOR(384), -- For pgvector extension (BGE-small dimensions)
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE TRIGGER update_documents_updated_at
  BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_documents_uploaded_by ON public.documents(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_documents_processing_status ON public.documents(processing_status);
CREATE INDEX IF NOT EXISTS idx_documents_created_at ON public.documents(created_at DESC);

-- Vector similarity search index (requires pgvector)
CREATE INDEX IF NOT EXISTS idx_documents_embedding ON public.documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ===========================================
-- CONVERSATIONS TABLE
-- ===========================================
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  project_id UUID,
  is_active BOOLEAN DEFAULT TRUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE TRIGGER update_conversations_updated_at
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON public.conversations(created_at DESC);

-- ===========================================
-- MESSAGES TABLE
-- ===========================================
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  message_type TEXT NOT NULL CHECK (message_type IN ('user', 'assistant')),
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at ASC);

-- ===========================================
-- CONVERSATION DOCUMENTS (linking table)
-- ===========================================
CREATE TABLE IF NOT EXISTS public.conversation_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  document_id UUID REFERENCES public.documents(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
  UNIQUE(conversation_id, document_id)
);

CREATE INDEX IF NOT EXISTS idx_conversation_documents_conversation_id ON public.conversation_documents(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_documents_document_id ON public.conversation_documents(document_id);

-- ===========================================
-- AUDIT LOGS TABLE
-- ===========================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  details JSONB,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_resource ON public.audit_logs(resource_type, resource_id);

-- ===========================================
-- SYSTEM STATS TABLE
-- ===========================================
CREATE TABLE IF NOT EXISTS public.system_stats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  metric_name TEXT NOT NULL,
  metric_value BIGINT NOT NULL,
  recorded_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_system_stats_metric_name ON public.system_stats(metric_name);
CREATE INDEX IF NOT EXISTS idx_system_stats_recorded_at ON public.system_stats(recorded_at DESC);

-- ===========================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ===========================================

-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_stats ENABLE ROW LEVEL SECURITY;

-- ===========================================
-- USERS POLICIES
-- ===========================================

-- Users can read their own profile
CREATE POLICY "Users can view own profile" ON public.users
  FOR SELECT USING (auth.uid() = id);

-- Users can update their own profile (except role and is_active)
CREATE POLICY "Users can update own profile" ON public.users
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role = (SELECT role FROM public.users WHERE id = auth.uid()) -- Cannot change own role
    AND is_active = (SELECT is_active FROM public.users WHERE id = auth.uid()) -- Cannot change own active status
  );

-- Admins can view all users
CREATE POLICY "Admins can view all users" ON public.users
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role IN ('admin', 'super_admin')
      AND is_active = true
    )
  );

-- Admins can update user profiles
CREATE POLICY "Admins can update users" ON public.users
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role IN ('admin', 'super_admin')
      AND is_active = true
    )
  );

-- Super admins can do everything
CREATE POLICY "Super admins have full access" ON public.users
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role = 'super_admin'
      AND is_active = true
    )
  );

-- ===========================================
-- DOCUMENTS POLICIES
-- ===========================================

-- Users can view documents they uploaded
CREATE POLICY "Users can view own documents" ON public.documents
  FOR SELECT USING (auth.uid() = uploaded_by);

-- Users can insert their own documents
CREATE POLICY "Users can upload documents" ON public.documents
  FOR INSERT WITH CHECK (auth.uid() = uploaded_by);

-- Users can update their own documents
CREATE POLICY "Users can update own documents" ON public.documents
  FOR UPDATE USING (auth.uid() = uploaded_by);

-- Users can delete their own documents
CREATE POLICY "Users can delete own documents" ON public.documents
  FOR DELETE USING (auth.uid() = uploaded_by);

-- Admins can view all documents
CREATE POLICY "Admins can view all documents" ON public.documents
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role IN ('admin', 'super_admin')
      AND is_active = true
    )
  );

-- ===========================================
-- CONVERSATIONS POLICIES
-- ===========================================

-- Users can view their own conversations
CREATE POLICY "Users can view own conversations" ON public.conversations
  FOR SELECT USING (auth.uid() = user_id);

-- Users can create their own conversations
CREATE POLICY "Users can create conversations" ON public.conversations
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own conversations
CREATE POLICY "Users can update own conversations" ON public.conversations
  FOR UPDATE USING (auth.uid() = user_id);

-- Users can delete their own conversations
CREATE POLICY "Users can delete own conversations" ON public.conversations
  FOR DELETE USING (auth.uid() = user_id);

-- ===========================================
-- MESSAGES POLICIES
-- ===========================================

-- Users can view messages in their own conversations
CREATE POLICY "Users can view messages in own conversations" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = messages.conversation_id
      AND user_id = auth.uid()
    )
  );

-- Users can insert messages in their own conversations
CREATE POLICY "Users can insert messages in own conversations" ON public.messages
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = messages.conversation_id
      AND user_id = auth.uid()
    )
  );

-- Users can update messages in their own conversations
CREATE POLICY "Users can update messages in own conversations" ON public.messages
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = messages.conversation_id
      AND user_id = auth.uid()
    )
  );

-- Users can delete messages in their own conversations
CREATE POLICY "Users can delete messages in own conversations" ON public.messages
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = messages.conversation_id
      AND user_id = auth.uid()
    )
  );

-- ===========================================
-- CONVERSATION DOCUMENTS POLICIES
-- ===========================================

-- Users can view conversation documents for their conversations
CREATE POLICY "Users can view conversation documents" ON public.conversation_documents
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = conversation_documents.conversation_id
      AND user_id = auth.uid()
    )
  );

-- Users can manage conversation documents for their conversations
CREATE POLICY "Users can manage conversation documents" ON public.conversation_documents
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = conversation_documents.conversation_id
      AND user_id = auth.uid()
    )
  );

-- ===========================================
-- AUDIT LOGS POLICIES
-- ===========================================

-- Only admins can view audit logs
CREATE POLICY "Admins can view audit logs" ON public.audit_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role IN ('admin', 'super_admin')
      AND is_active = true
    )
  );

-- System can insert audit logs
CREATE POLICY "System can insert audit logs" ON public.audit_logs
  FOR INSERT WITH CHECK (true);

-- ===========================================
-- SYSTEM STATS POLICIES
-- ===========================================

-- Only admins can view system stats
CREATE POLICY "Admins can view system stats" ON public.system_stats
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role IN ('admin', 'super_admin')
      AND is_active = true
    )
  );

-- System can insert stats
CREATE POLICY "System can insert system stats" ON public.system_stats
  FOR INSERT WITH CHECK (true);

-- ===========================================
-- FUNCTIONS AND TRIGGERS
-- ===========================================

-- Function to automatically create user profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create user profile on signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to create audit log entries
CREATE OR REPLACE FUNCTION public.create_audit_log(
  p_user_id UUID,
  p_action TEXT,
  p_resource_type TEXT,
  p_resource_id UUID DEFAULT NULL,
  p_details JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  audit_id UUID;
BEGIN
  INSERT INTO public.audit_logs (user_id, p_action, resource_type, resource_id, details)
  VALUES (p_user_id, p_action, p_resource_type, p_resource_id, p_details)
  RETURNING id INTO audit_id;

  RETURN audit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get system statistics
CREATE OR REPLACE FUNCTION public.get_system_stats()
RETURNS TABLE (
  total_users BIGINT,
  active_users BIGINT,
  total_documents BIGINT,
  total_conversations BIGINT,
  total_messages BIGINT,
  storage_used_bytes BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM public.users WHERE is_active = true) as total_users,
    (SELECT COUNT(*) FROM public.users WHERE is_active = true) as active_users,
    (SELECT COUNT(*) FROM public.documents) as total_documents,
    (SELECT COUNT(*) FROM public.conversations) as total_conversations,
    (SELECT COUNT(*) FROM public.messages) as total_messages,
    (SELECT COALESCE(SUM(file_size), 0) FROM public.documents) as storage_used_bytes;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===========================================
-- STORAGE BUCKET POLICIES
-- ===========================================

-- Create documents bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  10485760, -- 10MB limit
  ARRAY['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/plain', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
) ON CONFLICT (id) DO NOTHING;

-- Storage policies for documents bucket
CREATE POLICY "Users can upload their own documents" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can view their own documents" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can update their own documents" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete their own documents" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Admins can access all documents
CREATE POLICY "Admins can access all documents" ON storage.objects
  FOR ALL USING (
    bucket_id = 'documents'
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role IN ('admin', 'super_admin')
      AND is_active = true
    )
  );

-- ===========================================
-- INITIAL DATA (Optional)
-- ===========================================

-- Insert system stats record (will be updated by application)
INSERT INTO public.system_stats (metric_name, metric_value) VALUES
  ('total_users', 0),
  ('active_users', 0),
  ('total_documents', 0),
  ('total_conversations', 0),
  ('total_messages', 0),
  ('storage_used_bytes', 0)
ON CONFLICT DO NOTHING;

-- ===========================================
-- PERFORMANCE OPTIMIZATIONS
-- ===========================================

-- Create partial indexes for better performance
CREATE INDEX IF NOT EXISTS idx_users_active ON public.users(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_conversations_active ON public.conversations(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_documents_completed ON public.documents(processing_status) WHERE processing_status = 'completed';

-- Create composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_documents_user_status ON public.documents(uploaded_by, processing_status);
CREATE INDEX IF NOT EXISTS idx_conversations_user_active ON public.conversations(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_type ON public.messages(conversation_id, message_type);

-- ===========================================
-- COMMENTS FOR DOCUMENTATION
-- ===========================================

COMMENT ON TABLE public.users IS 'User profiles extending Supabase auth.users with additional metadata';
COMMENT ON TABLE public.documents IS 'Document storage with metadata and AI processing results';
COMMENT ON TABLE public.conversations IS 'Chat conversations between users and AI';
COMMENT ON TABLE public.messages IS 'Individual messages within conversations';
COMMENT ON TABLE public.conversation_documents IS 'Links conversations to relevant documents';
COMMENT ON TABLE public.audit_logs IS 'Audit trail for system activities';
COMMENT ON TABLE public.system_stats IS 'System-wide statistics and metrics';

COMMENT ON COLUMN public.documents.embedding IS 'Vector embedding for semantic search using pgvector';
COMMENT ON COLUMN public.users.role IS 'User role for RBAC: super_admin, admin, user, guest';

-- ===========================================
-- END OF SCHEMA
-- ===========================================