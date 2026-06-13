import express from 'express';
import cors from 'cors';
import multer from 'multer';
import dotenv from 'dotenv';
import authRoutes from './routes/auth.routes';
import restaurantRoutes from './routes/restaurant.routes';
import ordersRoutes from './routes/orders.routes';
import menuRoutes from './routes/menu.routes';
import publicRoutes from './routes/public.routes';
import uploadRoutes from './routes/upload.routes';
import fcmRoutes from './routes/fcm.routes';
import { supabase } from './db/supabase';

dotenv.config();

const app = express();

app.use(cors());

// 1MB JSON limit is plenty for auth / app data (uploads use multipart)
app.use(express.json({ limit: '1mb' }));

// Multer: memory storage, 5MB file limit per upload
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

// Apply multer to upload route — parses multipart/form-data, populates req.file
app.use('/api/upload', upload.single('file'), uploadRoutes);

app.get('/', (_req, res) => {
  res.json({ status: 'ok', message: 'Food Delivery API is running' });
});

app.use('/api/auth', authRoutes);
app.use('/api/restaurant-applications', restaurantRoutes);
app.use('/api/orders', ordersRoutes);
app.use('/api/menu', menuRoutes);
app.use('/api/restaurants', publicRoutes);
app.use('/api/fcm', fcmRoutes);

const PORT = Number(process.env.PORT) || 5000;

const REQUIRED_BUCKETS = [
  { name: 'pan-certificates', public: true },
  { name: 'restaurant-images', public: true },
  { name: 'food-images', public: true },
];

async function ensureStorageBuckets(): Promise<void> {
  console.log('[setup] Checking Supabase storage buckets...');

  const { data: existing, error: listError } = await supabase.admin.storage.listBuckets();
  if (listError) {
    console.warn('[setup] Could not list storage buckets:', listError.message);
    return;
  }

  const existingNames = new Set(existing.map((b) => b.name));

  for (const bucket of REQUIRED_BUCKETS) {
    if (existingNames.has(bucket.name)) {
      console.log(`[setup] Bucket "${bucket.name}" already exists.`);
    } else {
      console.log(`[setup] Creating bucket "${bucket.name}"...`);
      const { error: createError } = await supabase.admin.storage.createBucket(bucket.name, {
        public: bucket.public,
      });
      if (createError) {
        console.warn(`[setup] Failed to create bucket "${bucket.name}":`, createError.message);
      } else {
        console.log(`[setup] Bucket "${bucket.name}" created (public: ${bucket.public}).`);
      }
    }
  }
}

app.listen(PORT, '0.0.0.0', async () => {
  console.log(`Server is running on port ${PORT}`);
  console.log(`Listening on http://0.0.0.0:${PORT} (accessible from network)`);

  try {
    await ensureStorageBuckets();
  } catch (err) {
    console.warn('[setup] Storage bucket setup failed:', (err as Error).message);
  }
});

export default app;
