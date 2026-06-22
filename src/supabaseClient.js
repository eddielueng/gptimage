import { createClient } from '@supabase/supabase-js';

const rawUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// Support reverse proxy: if VITE_SUPABASE_URL is a relative path (e.g. /supabase-proxy),
// convert it to an absolute URL using the current origin
const supabaseUrl = rawUrl?.startsWith('/')
  ? `${window.location.origin}${rawUrl}`
  : rawUrl;

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey, {
      auth: {
        autoRefreshToken: true,
        detectSessionInUrl: true,
        persistSession: true
      }
    })
  : null;
