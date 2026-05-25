import { Request, Response } from 'express';
import { prisma } from '../db/prisma';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

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
