import { Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import { randomBytes } from 'crypto';
import { supabase } from '../db/supabase';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const googleClient = new OAuth2Client(GOOGLE_CLIENT_ID);

// ──────────────────────────────────────────────
// Register
// ──────────────────────────────────────────────
export const register = async (req: Request, res: Response): Promise<void> => {
  try {
    const { username, email, phone, password } = req.body;

    if (!username || !email || !phone || !password) {
      res.status(400).json({ error: 'Missing required fields' });
      return;
    }

    // Check for existing user by email, username, or phone
    const { data: existingUser } = await supabase.admin
      .from('users')
      .select('id')
      .or(`email.eq.${email},username.eq.${username},phone.eq.${phone}`)
      .limit(1)
      .maybeSingle();

    if (existingUser) {
      res.status(409).json({ error: 'User already exists' });
      return;
    }

    const password_hash = await bcrypt.hash(password, 10);

    // Create auth user in supabase.auth.users first
    const tempPassword = randomBytes(8).toString('hex');
    const { data: authData, error: authError } = await supabase.admin.auth.admin.createUser({
      email,
      phone,
      password: tempPassword,
      email_confirm: true,
      phone_confirm: true,
      user_metadata: { username },
    });

    if (authError || !authData.user) {
      console.error('Supabase auth user create error:', authError);
      res.status(500).json({ error: 'Failed to create user' });
      return;
    }

    // Upsert into public users table using the auth user's ID
    const { data: user, error } = await supabase.admin
      .from('users')
      .upsert({
        id: authData.user.id,
        username,
        email,
        phone,
        password_hash,
        role: 'CUSTOMER',
      }, { onConflict: 'id' })
      .select('id, username, email, role')
      .single();

    if (error || !user) {
      console.error('Supabase upsert error:', error);
      await supabase.admin.auth.admin.deleteUser(authData.user.id).catch(() => {});
      res.status(500).json({ error: 'Failed to create user' });
      return;
    }

    const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1d' });

    res.status(201).json({
      message: 'User created successfully',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        role: user.role,
      },
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// Login
// ──────────────────────────────────────────────
export const login = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, phone, password } = req.body;

    if ((!email && !phone) || !password) {
      res.status(400).json({ error: 'Email or phone, and password are required' });
      return;
    }

    let query = supabase.admin.from('users').select('*');
    if (email && phone) {
      query = query.or(`email.eq.${email},phone.eq.${phone}`);
    } else if (email) {
      query = query.eq('email', email);
    } else if (phone) {
      query = query.eq('phone', phone);
    }

    const { data: user } = await query.limit(1).maybeSingle();

    if (!user || !user.password_hash) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }

    const isMatch = await bcrypt.compare(password, user.password_hash);

    if (!isMatch) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }

    const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1d' });

    res.status(200).json({
      message: 'Logged in successfully',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        role: user.role,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// Google Auth
// ──────────────────────────────────────────────
export const googleAuth = async (req: Request, res: Response): Promise<void> => {
  try {
    const { idToken } = req.body;

    if (!idToken) {
      res.status(400).json({ error: 'idToken is required' });
      return;
    }

    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: GOOGLE_CLIENT_ID ? [GOOGLE_CLIENT_ID] : undefined,
    });

    const payload = ticket.getPayload();
    if (!payload) {
      res.status(401).json({ error: 'Invalid Google token' });
      return;
    }

    const { email, name, sub: google_id } = payload;

    if (!email || !google_id) {
      res.status(400).json({ error: 'Email and google_id required from token' });
      return;
    }

    // Look up existing user by google_id or email
    let { data: user } = await supabase.admin
      .from('users')
      .select('*')
      .or(`google_id.eq.${google_id},email.eq.${email}`)
      .limit(1)
      .maybeSingle();

    if (user) {
      // Link google_id if not set
      if (!user.google_id) {
        const { data: updated } = await supabase.admin
          .from('users')
          .update({ google_id })
          .eq('id', user.id)
          .select('*')
          .single();

        if (updated) user = updated;
      }

      // If user has a real phone (not TEMP_), they're fully registered
      if (user.phone && !user.phone.startsWith('TEMP_')) {
        const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1d' });
        res.status(200).json({
          message: 'Logged in successfully',
          token,
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            role: user.role,
          },
        });
        return;
      }

      // Profile completion needed
      const temp_token = jwt.sign({ google_id }, JWT_SECRET, { expiresIn: '1h' });
      res.status(200).json({
        requires_profile_completion: true,
        temp_token,
      });
      return;
    }

    // New user — create placeholder
    const tempPhone = `TEMP_${google_id}`;
    const tempUsername = `user_${google_id.substring(0, 8)}`;

    // Create auth user in supabase.auth.users first
    const tempPassword = randomBytes(8).toString('hex');
    const { data: authData, error: authError } = await supabase.admin.auth.admin.createUser({
      email,
      email_confirm: true,
      password: tempPassword,
      user_metadata: { name, username: tempUsername },
    });

    if (authError || !authData.user) {
      console.error('Supabase auth user create error:', authError);
      res.status(500).json({ error: 'Failed to create user' });
      return;
    }

    // Upsert into public users table using the auth user's ID
    const { error: insertError } = await supabase.admin
      .from('users')
      .upsert({
        id: authData.user.id,
        email,
        google_id,
        phone: tempPhone,
        username: tempUsername,
      }, { onConflict: 'id' })
      .select()
      .single();

    if (insertError) {
      console.error('Supabase upsert error:', insertError);
      await supabase.admin.auth.admin.deleteUser(authData.user.id).catch(() => {});
      res.status(500).json({ error: 'Failed to create user' });
      return;
    }

    const temp_token = jwt.sign({ google_id }, JWT_SECRET, { expiresIn: '1h' });
    res.status(200).json({
      requires_profile_completion: true,
      temp_token,
    });
  } catch (error) {
    console.error('Google auth error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// Complete Profile (after Google sign-in)
// ──────────────────────────────────────────────
export const completeProfile = async (req: Request, res: Response): Promise<void> => {
  try {
    const { temp_token, phone, username } = req.body;

    if (!temp_token || !phone || !username) {
      res.status(400).json({ error: 'temp_token, phone, and username are required' });
      return;
    }

    let payload: { google_id: string };
    try {
      payload = jwt.verify(temp_token, JWT_SECRET) as { google_id: string };
    } catch {
      res.status(401).json({ error: 'Invalid or expired temp token' });
      return;
    }

    const { google_id } = payload;

    const { data: user } = await supabase.admin
      .from('users')
      .select('*')
      .eq('google_id', google_id)
      .maybeSingle();

    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    // Check if phone or username is taken by another user
    const { data: existing } = await supabase.admin
      .from('users')
      .select('id')
      .neq('id', user.id)
      .or(`phone.eq.${phone},username.eq.${username}`)
      .limit(1)
      .maybeSingle();

    if (existing) {
      res.status(409).json({ error: 'Phone or username already in use' });
      return;
    }

    const { data: updatedUser, error } = await supabase.admin
      .from('users')
      .update({ phone, username })
      .eq('id', user.id)
      .select('id, username, email, role')
      .single();

    if (error || !updatedUser) {
      res.status(500).json({ error: 'Failed to update profile' });
      return;
    }

    const token = jwt.sign({ id: updatedUser.id, role: updatedUser.role }, JWT_SECRET, { expiresIn: '1d' });

    res.status(200).json({
      message: 'Profile completed successfully',
      token,
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        role: updatedUser.role,
      },
    });
  } catch (error) {
    console.error('Complete profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ══════════════════════════════════════════════
// OTP Configuration
// ══════════════════════════════════════════════

const OTP_EXPIRY_MINUTES = 10;
const OTP_MAX_ATTEMPTS = 5;
const RATE_LIMIT_MAX_REQUESTS = 3;
const RATE_LIMIT_WINDOW_MINUTES = 10;
const RATE_LIMIT_BLOCK_MINUTES = 30;
const TEXTBEE_API_URL = process.env.TEXTBEE_API_URL || 'https://api.textbee.io/api/v1/send';
const TEXTBEE_API_KEY = process.env.TEXTBEE_API_KEY || '';
const NEPAL_COUNTRY_CODE = process.env.COUNTRY_CODE || '+977';

function generateOtp(): string {
  const buffer = randomBytes(4);
  const num = buffer.readUInt32BE(0) % 1000000;
  return num.toString().padStart(6, '0');
}

function formatPhoneForSms(phone: string): string {
  if (phone.startsWith('+')) return phone;
  if (/^\d{10}$/.test(phone)) {
    return `${NEPAL_COUNTRY_CODE}${phone}`;
  }
  return phone;
}

async function sendSmsViaTextBee(phone: string, message: string): Promise<boolean> {
  const formattedPhone = formatPhoneForSms(phone);

  if (!TEXTBEE_API_KEY) {
    console.warn('TEXTBEE_API_KEY not configured — SMS not sent.');
    return true;
  }

  try {
    const response = await fetch(TEXTBEE_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': TEXTBEE_API_KEY,
      },
      body: JSON.stringify({ phone: formattedPhone, message }),
    });

    if (!response.ok) {
      console.error('TextBee SMS failed:', await response.text());
      return false;
    }
    return true;
  } catch (error) {
    console.error('TextBee SMS error:', error);
    return false;
  }
}

// ──────────────────────────────────────────────
// POST /api/auth/check-availability
// ──────────────────────────────────────────────
export const checkAvailability = async (req: Request, res: Response): Promise<void> => {
  try {
    const { username, phone, email } = req.body;

    if (!username && !phone && !email) {
      res.status(400).json({ error: 'At least one of username, phone, or email is required' });
      return;
    }

    const taken: { username?: boolean; phone?: boolean; email?: boolean } = {};

    const conditions: string[] = [];
    if (username) conditions.push(`username.eq.${username}`);
    if (phone) conditions.push(`phone.eq.${phone}`);
    if (email) conditions.push(`email.eq.${email}`);

    const { data: existingUsers } = await supabase.admin
      .from('users')
      .select('username, phone, email')
      .or(conditions.join(','))
      .limit(10);

    if (existingUsers) {
      for (const user of existingUsers) {
        if (username && user.username === username) taken.username = true;
        if (phone && user.phone === phone) taken.phone = true;
        if (email && user.email === email) taken.email = true;
      }
    }

    const isAvailable = !taken.username && !taken.phone && !taken.email;

    res.status(200).json({
      available: isAvailable,
      taken,
    });
  } catch (error) {
    console.error('Check availability error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/auth/send-otp
// ──────────────────────────────────────────────
export const sendOtp = async (req: Request, res: Response): Promise<void> => {
  try {
    const { phone, purpose } = req.body;

    if (!phone || !purpose) {
      res.status(400).json({ error: 'Phone and purpose are required' });
      return;
    }

    const validPurposes = ['LOGIN', 'SIGNUP', 'RESET'];
    if (!validPurposes.includes(purpose)) {
      res.status(400).json({ error: `Invalid purpose. Must be one of: ${validPurposes.join(', ')}` });
      return;
    }

    const now = new Date();
    const windowStart = new Date(now.getTime() - RATE_LIMIT_WINDOW_MINUTES * 60 * 1000);

    // ── Rate limit check ──────────────────────
    const { data: existingLimit } = await supabase.admin
      .from('otp_rate_limits')
      .select('*')
      .eq('phone', phone)
      .order('window_start', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingLimit) {
      // Check if blocked
      if (existingLimit.blocked_until && new Date(existingLimit.blocked_until) > now) {
        const minutesLeft = Math.ceil(
          (new Date(existingLimit.blocked_until).getTime() - now.getTime()) / 60000,
        );
        res.status(429).json({
          error: `Too many requests. Try again in ${minutesLeft} minute(s).`,
          blocked_until: existingLimit.blocked_until,
        });
        return;
      }

      // Check if within same window
      if (new Date(existingLimit.window_start) > windowStart) {
        if ((existingLimit.request_count ?? 0) >= RATE_LIMIT_MAX_REQUESTS) {
          const blockedUntil = new Date(now.getTime() + RATE_LIMIT_BLOCK_MINUTES * 60 * 1000);
          await supabase.admin
            .from('otp_rate_limits')
            .update({ blocked_until: blockedUntil.toISOString() })
            .eq('id', existingLimit.id);

          res.status(429).json({
            error: `Too many requests. Try again in ${RATE_LIMIT_BLOCK_MINUTES} minute(s).`,
            blocked_until: blockedUntil.toISOString(),
          });
          return;
        }

        // Increment count
        await supabase.admin
          .from('otp_rate_limits')
          .update({ request_count: (existingLimit.request_count ?? 0) + 1 })
          .eq('id', existingLimit.id);
      } else {
        // New window — reset
        await supabase.admin
          .from('otp_rate_limits')
          .update({
            request_count: 1,
            window_start: now.toISOString(),
            blocked_until: null,
          })
          .eq('id', existingLimit.id);
      }
    } else {
      // First request — create entry
      await supabase.admin
        .from('otp_rate_limits')
        .insert({
          phone,
          request_count: 1,
          window_start: now.toISOString(),
        });
    }

    // ── Generate & hash OTP ───────────────────
    const otp = generateOtp();
    const otpHash = await bcrypt.hash(otp, 10);
    const expiresAt = new Date(now.getTime() + OTP_EXPIRY_MINUTES * 60 * 1000);

    await supabase.admin
      .from('otp_requests')
      .insert({
        phone,
        purpose,
        otp_hash: otpHash,
        max_attempts: OTP_MAX_ATTEMPTS,
        expires_at: expiresAt.toISOString(),
      });

    // ── Send SMS via TextBee ──────────────────
    if (!TEXTBEE_API_KEY) {
      console.warn(`🔐 [DEV] OTP for ${phone}: ${otp} (expires in ${OTP_EXPIRY_MINUTES} min)`);
    }
    const smsSent = await sendSmsViaTextBee(
      phone,
      `Your verification code is: ${otp}. It expires in ${OTP_EXPIRY_MINUTES} minutes.`,
    );

    if (!smsSent) {
      res.status(500).json({ error: 'Failed to send SMS. Please try again.' });
      return;
    }

    res.status(200).json({
      message: 'OTP sent successfully',
      expires_at: expiresAt.toISOString(),
    });
  } catch (error) {
    console.error('Send OTP error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/auth/verify-otp
// ──────────────────────────────────────────────
export const verifyOtp = async (req: Request, res: Response): Promise<void> => {
  try {
    const { phone, otp, username } = req.body;

    if (!phone || !otp) {
      res.status(400).json({ error: 'Phone and OTP are required' });
      return;
    }

    // ── Fetch latest unverified OTP request ───
    const { data: otpRequest } = await supabase.admin
      .from('otp_requests')
      .select('*')
      .eq('phone', phone)
      .is('verified_at', null)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!otpRequest) {
      res.status(400).json({ error: 'No OTP request found. Please request a new OTP.' });
      return;
    }

    const now = new Date();

    // ── Check expiry ──────────────────────────
    if (now > new Date(otpRequest.expires_at)) {
      res.status(400).json({ error: 'OTP has expired. Please request a new one.' });
      return;
    }

    // ── Check attempts ────────────────────────
    if ((otpRequest.attempts ?? 0) >= (otpRequest.max_attempts ?? OTP_MAX_ATTEMPTS)) {
      res.status(429).json({ error: 'Maximum OTP attempts exceeded. Please request a new OTP.' });
      return;
    }

    // ── Increment attempts (before compare, to prevent timing attacks) ──
    await supabase.admin
      .from('otp_requests')
      .update({ attempts: (otpRequest.attempts ?? 0) + 1 })
      .eq('id', otpRequest.id);

    // ── Compare hash ──────────────────────────
    const isValid = await bcrypt.compare(otp, otpRequest.otp_hash);

    if (!isValid) {
      const attemptsLeft = (otpRequest.max_attempts ?? OTP_MAX_ATTEMPTS) - ((otpRequest.attempts ?? 0) + 1);
      if (attemptsLeft <= 0) {
        res.status(429).json({ error: 'Maximum OTP attempts exceeded. Please request a new OTP.' });
      } else {
        res.status(400).json({
          error: `Invalid OTP. ${attemptsLeft} attempt(s) remaining.`,
          attempts_left: attemptsLeft,
        });
      }
      return;
    }

    // ── Mark as verified ──────────────────────
    await supabase.admin
      .from('otp_requests')
      .update({ verified_at: now.toISOString() })
      .eq('id', otpRequest.id);

    // ── Create or fetch user ──────────────────
    const purpose = otpRequest.purpose;

    const { data: existingUser } = await supabase.admin
      .from('users')
      .select('*')
      .eq('phone', phone)
      .maybeSingle();

    let user = existingUser;

    if (!user) {
      if (purpose === 'LOGIN') {
        res.status(404).json({ error: 'No account found with this phone number. Please sign up first.' });
        return;
      }

      // SIGNUP — create user
      if (!username) {
        res.status(400).json({ error: 'Username is required for registration' });
        return;
      }

      // Check username uniqueness
      const { data: existingUsername } = await supabase.admin
        .from('users')
        .select('id')
        .eq('username', username)
        .maybeSingle();

      if (existingUsername) {
        res.status(409).json({ error: 'Username already taken' });
        return;
      }

      // Create auth user in supabase auth.users first
      const tempPassword = randomBytes(8).toString('hex');
      const { data: authData, error: authError } = await supabase.admin.auth.admin.createUser({
        email: `${phone}@placeholder.local`,
        phone,
        password: tempPassword,
        email_confirm: true,
        phone_confirm: true,
        user_metadata: { username },
      });

      if (authError || !authData.user) {
        console.error('Supabase auth user create error:', authError);
        res.status(500).json({ error: 'Failed to create user' });
        return;
      }

      // Upsert into public users table — uses the auth user's ID.
      // Supabase may auto-create a public row via trigger on auth.users creation,
      // so upsert handles both the trigger-created and fresh-insert cases.
      const { data: newUser, error: upsertError } = await supabase.admin
        .from('users')
        .upsert({
          id: authData.user.id,
          username,
          email: `${phone}@placeholder.local`,
          phone,
          role: 'CUSTOMER',
        }, { onConflict: 'id' })
        .select('*')
        .single();

      if (upsertError || !newUser) {
        console.error('Supabase public user upsert error:', upsertError);
        await supabase.admin.auth.admin.deleteUser(authData.user.id).catch(() => {});
        res.status(500).json({ error: 'Failed to create user' });
        return;
      }

      user = newUser;
    }

    // ── Generate JWT ──────────────────────────
    const token = jwt.sign(
      { id: user.id, role: user.role, phone: user.phone },
      JWT_SECRET,
      { expiresIn: '7d' },
    );

    res.status(200).json({
      message: 'OTP verified successfully',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        phone: user.phone,
        role: user.role,
      },
    });
  } catch (error) {
    console.error('Verify OTP error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
