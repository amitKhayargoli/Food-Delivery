import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

interface JwtPayload {
  id: string;
  role: string;
}

// Allowed buckets
const ALLOWED_BUCKETS = ['pan-certificates', 'restaurant-images', 'food-images'];

const MIME_MAP: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  gif: 'image/gif',
  bmp: 'image/bmp',
  svg: 'image/svg+xml',
  webp: 'image/webp',
  pdf: 'application/pdf',
};

// ──────────────────────────────────────────────
// POST /api/upload
// Upload a file to Supabase Storage via service_role key (bypasses RLS)
// Uses multer multipart: field name = "file"
// Additional fields: bucket (string)
// ──────────────────────────────────────────────
export const uploadFile = async (req: Request, res: Response): Promise<void> => {
  try {
    // Auth check
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    let userId: string;
    try {
      const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as JwtPayload;
      userId = payload.id;
    } catch {
      res.status(401).json({ error: 'Invalid or expired token' });
      return;
    }

    // Validate bucket
    const bucket = req.body.bucket as string | undefined;
    if (!bucket || !ALLOWED_BUCKETS.includes(bucket)) {
      res.status(400).json({ error: `Invalid bucket. Allowed: ${ALLOWED_BUCKETS.join(', ')}` });
      return;
    }

    // Validate file
    if (!req.file) {
      res.status(400).json({ error: 'No file uploaded. Use field name "file".' });
      return;
    }

    // Validate file size (max 5MB)
    if (req.file.size > 5 * 1024 * 1024) {
      res.status(400).json({ error: 'File size exceeds 5MB limit.' });
      return;
    }

    // Generate a unique file name
    // If a custom path is provided (e.g. 'logos/my_logo.jpg'), use it;
    // otherwise default to userId_timestamp.ext
    const ext = req.file.originalname.split('.').pop()?.toLowerCase() || 'jpg';
    const timestamp = Date.now();
    const customPath = req.body.path as string | undefined;
    const fileName = customPath ?? `${userId}_${timestamp}.${ext}`;
    const contentType = MIME_MAP[ext] || req.file.mimetype || 'application/octet-stream';

    // Upload using service_role client (bypasses RLS)
    const { data, error } = await supabase.admin.storage
      .from(bucket)
      .upload(fileName, req.file.buffer, {
        contentType,
        upsert: false,
      });

    if (error) {
      console.error('[upload] Supabase storage error:', error);
      res.status(500).json({ error: 'Failed to upload file: ' + error.message });
      return;
    }

    // Get the public URL
    const publicUrl = supabase.admin.storage.from(bucket).getPublicUrl(fileName).data.publicUrl;

    res.status(200).json({
      message: 'File uploaded successfully',
      url: publicUrl,
      fileName,
    });
  } catch (error) {
    console.error('[upload] Upload error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
