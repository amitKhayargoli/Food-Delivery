import { Request, Response } from 'express';
import { prisma } from '../db/prisma';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const googleClient = new OAuth2Client(GOOGLE_CLIENT_ID);

export const register = async (req: Request, res: Response): Promise<void> => {
  try {
    const { username, email, phone, password } = req.body;

    if (!username || !email || !phone || !password) {
      res.status(400).json({ error: 'Missing required fields' });
      return;
    }

    const existingUser = await prisma.user.findFirst({
      where: {
        OR: [
          { email },
          { username },
          { phone }
        ]
      }
    });

    if (existingUser) {
      res.status(409).json({ error: 'User already exists' });
      return;
    }

    const password_hash = await bcrypt.hash(password, 10);

    const user = await prisma.user.create({
      data: {
        username,
        email,
        phone,
        password_hash
      }
    });

    const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1d' });

    res.status(201).json({
      message: 'User created successfully',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        role: user.role
      }
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const login = async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, phone, password } = req.body;

    if ((!email && !phone) || !password) {
      res.status(400).json({ error: 'Email or phone, and password are required' });
      return;
    }

    const user = await prisma.user.findFirst({
      where: {
        OR: [
          email ? { email } : {},
          phone ? { phone } : {}
        ].filter(x => Object.keys(x).length > 0)
      }
    });

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
        role: user.role
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

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

    let user = await prisma.user.findFirst({
      where: {
        OR: [
          { google_id },
          { email }
        ]
      }
    });

    if (user) {
      if (!user.google_id) {
        user = await prisma.user.update({
          where: { id: user.id },
          data: { google_id }
        });
      }

      if (user.phone && !user.phone.startsWith('TEMP_')) {
        const token = jwt.sign({ id: user.id, role: user.role }, JWT_SECRET, { expiresIn: '1d' });
        res.status(200).json({
          message: 'Logged in successfully',
          token,
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            role: user.role
          }
        });
        return;
      }
      
      const temp_token = jwt.sign({ google_id }, JWT_SECRET, { expiresIn: '1h' });
      res.status(200).json({ 
        requires_profile_completion: true, 
        temp_token 
      });
      return;
    }

    const tempPhone = `TEMP_${google_id}`;
    const tempUsername = `user_${google_id}`;

    user = await prisma.user.create({
      data: {
        email,
        google_id,
        phone: tempPhone,
        username: tempUsername
      }
    });

    const temp_token = jwt.sign({ google_id }, JWT_SECRET, { expiresIn: '1h' });
    res.status(200).json({ 
      requires_profile_completion: true, 
      temp_token 
    });

  } catch (error) {
    console.error('Google auth error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const completeProfile = async (req: Request, res: Response): Promise<void> => {
  try {
    const { temp_token, phone, username } = req.body;

    if (!temp_token || !phone || !username) {
      res.status(400).json({ error: 'temp_token, phone, and username are required' });
      return;
    }

    let payload;
    try {
      payload = jwt.verify(temp_token, JWT_SECRET) as { google_id: string };
    } catch (e) {
      res.status(401).json({ error: 'Invalid or expired temp token' });
      return;
    }

    const { google_id } = payload;

    const user = await prisma.user.findUnique({
      where: { google_id }
    });

    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const existing = await prisma.user.findFirst({
      where: {
        id: { not: user.id },
        OR: [
          { phone },
          { username }
        ]
      }
    });

    if (existing) {
      res.status(409).json({ error: 'Phone or username already in use' });
      return;
    }

    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: { phone, username }
    });

    const token = jwt.sign({ id: updatedUser.id, role: updatedUser.role }, JWT_SECRET, { expiresIn: '1d' });

    res.status(200).json({
      message: 'Profile completed successfully',
      token,
      user: {
        id: updatedUser.id,
        username: updatedUser.username,
        email: updatedUser.email,
        role: updatedUser.role
      }
    });

  } catch (error) {
    console.error('Complete profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
